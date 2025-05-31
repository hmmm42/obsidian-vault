LRU缓存中分段（segment）设计的原因
在CacheUseLRU的实现中，采用分段（segmented）设计有几个重要原因：

1. 减少锁竞争
   这是最主要的原因。代码注释中也明确提到：

It maintains multiple segments, each with its own lock, to reduce lock contention.

在高并发环境下，如果整个缓存共用一把锁，当多个协程同时尝试访问缓存时会产生严重的锁竞争，
导致性能下降。而分段设计让每个segment拥有自己独立的锁，不同key的操作可能落在不同segment上，
从而可以并行执行。

2. 提高并发性能
   通过哈希函数（FNV算法）将key分散到不同的segment中：

这种设计允许多个协程同时访问不同segment的数据，大大提高了并发读写性能。

3. 更细粒度的内存控制
   每个segment有自己的最大内存限制（maxBytes）：

这使得内存控制更加均匀和精细，不会出现某个区域过度占用内存的情况。

4. 更高效的过期清理
   在cleanupRoutine中，可以对各个segment分别进行清理，避免了清理过程中锁定整个缓存。清理一个segment时不会影响其他segment的正常使用。

5. 更好的扩展性
   这种分段设计使缓存系统更容易水平扩展，将来如果需要可以动态调整segment数量。

总结来说，这种分段设计是一种空间换时间的策略，牺牲了少量内存（每个segment都有自己的数据结构），但换来了显著的并发性能提升，这在高并发系统中是非常值得的权衡

# etcd
`grpc.*Client`只在`Fetch`方法内被使用, `Fetcher`中的是`etcd`的`clientv3`

3个`client`区分
## `*clientv3.Client` (来自 go.etcd.io/etcd/client/v3)
作用: etcd 客户端。
职责: 与 etcd 服务器集群进行交互，用于服务注册、服务发现、租约管理等。
在代码中的位置:
作为 internal/transport/grpc/fetcher.go 中 Client 结构体的一个字段 (conn)。
在 pkg/etcd/discovery 和 pkg/etcd/registry 包中被创建和使用，以执行具体的 etcd 操作。
## Client (定义在 internal/transport/grpc/fetcher.go):
作用: 缓存数据获取器 / 对等节点交互发起者。这是您项目自定义的一个结构体。
职责: 实现了 cache.Fetcher 接口。它封装了从任意一个提供指定服务（由 serviceName 字段指定，例如 "GroupCache"）的远程对等节点获取缓存数据的发起逻辑。
内部结构: 持有服务名 (serviceName) 和一个 etcd 客户端 (clientv3.Client)。
核心方法 (Fetch):
当需要从远程节点获取数据时，会调用此方法。
它使用其内部的 etcd 客户端 (c.conn) 和服务名 (c.serviceName) 去调用 discovery.Discover。
discovery.Discover 利用 etcd 服务发现机制来查找并建立一个到某个可用 gRPC 服务端点（对等节点）的实际 gRPC 连接（即 grpc.ClientConn，见下一点）。
Fetch 随后使用这个临时的 grpc.ClientConn 来执行真正的 RPC 调用。
关键点: 这个 Client 结构体本身不是一个到特定 gRPC 对等节点的持久连接。它更像是一个“请求发起器”，知道如何通过 etcd 找到并连接到一个合适的目标节点来完成 Fetch 操作。它被存储在 picker.Server 的 clients map 中，与对等节点的地址关联，作为向该地址（或更准确地说，向负责该地址所代表的 key 的节点）发起请求的入口。
grpc.ClientConn

## `*grpc.ClientConn` (来自 google.golang.org/grpc)
作用: gRPC 连接。
职责: 代表一个到特定 gRPC 服务器端点的实际网络连接。
在代码中的位置:
在 pkg/etcd/discovery/discovery.go 的 Discover 函数内部通过 grpc.NewClient(...) 创建。这个创建过程利用了 etcd 解析器 (resolver) 来动态查找目标服务的地址。
这个 grpc.ClientConn 对象随后被传递给 pb.NewGroupCacheClient(conn)，用于创建可以发起 RPC 调用的 gRPC 客户端存根。
在 fetcher.go 的 Fetch 方法中，这个连接通常是临时的，在 Fetch 调用结束时通过 defer conn.Close() 关闭。

## 流程
