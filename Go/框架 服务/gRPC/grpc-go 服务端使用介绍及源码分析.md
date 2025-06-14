#toread 
#  grpc-go 服务端使用介绍及源码分析   
原创 小徐先生1212  小徐先生的编程世界   2023-03-18 11:17  
  
# 0 前言  
  
未来几周想和大家一起开启 grpc 领域的探索之旅. 由于 grpc 涉及的信息量很大，我会拆成多篇内容，每次聚焦于一些小的主题，和大家持续交流探讨. 本文是其中第一篇，会谈及以下内容：  
- • 使用 grpc 的背景介绍  
  
- • 展示 grpc-go 的基本用法  
  
- • grpc-go 服务端源码走读  
  
- • grpc-go 拦截器的使用介绍  
  
本文内容的目录树结构如下图：  
  
![](https://mmbiz.qpic.cn/mmbiz_png/3ic3aBqT2ibZufUicuib0lkicb5dEuYricbZrk5Bl67O4m1apwBt9gMPf4qgS546AtjyknGY1zvicLSslf83GkNdyic4sA/640?wx_fmt=png "")  
  
   
# 1 背景介绍  
## 1.1 rpc  
  
rpc，全称 remote process call（远程过程调用），是微服务架构下的一种通信模式. 这种通信模式下，一台服务器在调用远程机器的接口时，能够获得像调用本地方法一样的良好体验.  
  
![](https://mmbiz.qpic.cn/mmbiz_png/3ic3aBqT2ibZufUicuib0lkicb5dEuYricbZrkwQQ7ACEfJNvpgibMtJ30Nh3uGESN8CXkF6GWicFTacW6pqlx2GicNiaMibA/640?wx_fmt=png "")  
  
   
  
rpc 通常对标的是 restful 风格的 http 调用方式，下面开放地聊聊个人眼中 rpc 相较于 http 的优势所在：  
- • rpc 调用基于 sdk 方式，调用方法和出入参协议固定，stub 文件本身还能起到接口文档的作用，很大程度上优化了通信双方约定协议达成共识的成本.  
  
- • rpc 在传输层协议 tcp 基础之上，可以由实现框架自定义填充应用层协议细节，理论上存在着更高的上限  
  
事物往往具有多面性，一些优点在转换视角后可能也会成为对应的劣势，因此从另一个角度看，rpc 相较于 http 存在如下缺点：  
- • 基于 sdk 方式调用，灵活度低、开发成本高，更多地适合用于系统内部模块间的通信交互，不适合对外  
  
- • 用户自定义实现应用层协议，下限水平也很不稳定  
  
   
## 1.2 grpc-go  
  
rpc 领域中的一座大山是 google 的开源框架 grpc，框架本身基于 C++ 实现，但对应于几个主流语言也有相应的实现版本.  
  
我的主语言是 golang，因此，今天我会和大家一起聊聊 grpc-go 的有关内容.  
  
   
  
![](https://mmbiz.qpic.cn/mmbiz_png/3ic3aBqT2ibZufUicuib0lkicb5dEuYricbZrkS5XUDOiaQUCm0plr8AgTmU2FibRSt9NS1unicatQmKhtia46uhC08Knr5Q/640?wx_fmt=png "")  
  
   
  
grpc-go 是基于 go 语言实现的 grpc 框架，要知道 go 语言本身也是 google 实现的，因此 golang 和 grpc 都是 google 的亲儿子，两者的契合度也是没得说，敬请诸位放心食用。  
  
grpc-go 以 HTTP2 作为应用层协议，使用 protobuf （下文可能简称 pb）作为数据序列化协议以及接口定义语言。  
  
protobuf 开源地址为：https://github.com/protocolbuffers/protobuf-go 后续我们会单开一个篇章，和大家聊聊 protobuf 的底层实现原理，此处暂且按下不表.  
  
最后，晒一下 grpc-go 项目的开源地址：https://github.com/grpc/grpc-go  
  
![](https://mmbiz.qpic.cn/mmbiz_png/3ic3aBqT2ibZufUicuib0lkicb5dEuYricbZrk0cxz9Oj7ZsagZ2vuzriczciaTCia2dqnCeJ64vIsMjvYILYziaRCYcibf4g/640?wx_fmt=png "")  
  
   
# 2 grpc-go 使用教程  
  
开扒框架源码之前，首先向大家简单介绍一下 grpc-go 的基本使用方法.  
## 2.1 前置准备  
  
首先需要把依赖的 grpc-go 插件提前安装好，分为如下几步：  
  
**（1）安装 grpc**  
```
go get google.golang.org/grpc@latest
```  
  
   
  
**（2）安装 protocol buffer**  
  
根据操作系统型号，下载安装好对应版本的 protobuf 应用：  
  
https://github.com/google/protobuf/releases  
  
需要将 protobuf 执行文件所在的目录添加到环境变量 $PATH 当中.  
  
安装完成后，可以通过查看 protobuf 版本指令，校验安装是否成功  
```
protoc --version
```  
  
   
  
**（3）安装 protobuf -> pb.go 插件**  
```
go install google.golang.org/protobuf/cmd/protoc-gen-go@v1.28
```  
  
   
  
该插件的作用是，能够基于 .proto 文件一键生成 _pb.go 文件，对应内容为通信请求/响应参数的对象模型.  
  
go install 指令默认会将插件安装到 $GOPATH/bin 目录下. 需要确保 $GOPATH/bin 路径有被添加到环境路径 $PATH 当中.  
  
安装完成后，可以通过查看插件版本指令，校验安装是否成功  
```
protoc-gen-go --version
```  
  
   
  
**（4）安装 protobuf -> grpc.pb.go 插件**  
```
go install google.golang.org/grpc/cmd/protoc-gen-go-grpc@v1.2
```  
  
   
  
该插件的作用是，能够基于 .proto 文件生成 _grpc.pb.go，对应内容为通信服务框架代码.  
  
安装完成后，可以通过查看插件版本指令，校验安装是否成功  
```
protoc-gen-go-grpc --version
```  
  
   
## 2.2 pb 桩文件  
  
**（1）编写 protobuf 文件**  
```
syntax = "proto3"; // 固定语法前缀


option go_package = ".";  // 指定生成的Go代码在你项目中的导入路径


package pb; // 包名


// 定义服务
service HelloService {
    // SayHello 方法
    rpc SayHello (HelloReq) returns (HelloResp) {}
}


// 请求消息
message HelloReq {
    string name = 1;
}


// 响应消息
message HelloResp {
    string reply = 1
}
```  
  
   
  
该文件以 .proto 作为后缀，扮演着 grpc 客户端与服务端通信交互的接口定义语言（DDL）的角色.  
  
protobuf 的细节内容与底层原理，后续我们单开章节再作介绍，此处能理解其基本用法即可.  
  
上述内容中，抛开前置的固定语法标识外，分为三个核心部分：  
- • 定义业务处理服务 HelloService，声明业务方法的名称（SayHello）以及出入参协议（HelloReq/HelloResp）  
  
- • 遵循 protobuf 的风格，分别声明出入参的类型定义：HelloReq 和 HelloResp，其中分别包含了字符串类型的成员字段 name 和 reply  
  
   
  
**（2）生成 pb.go 文件**  
  
通过使用插件，可以在 .proto 文件基础上，一键生成对应的 go 代码.  
```
protoc --go_out=. --go-grpc_out=. pb/hello.proto
```  
  
--go_out：指定 pb.go 文件的生成位置  
  
--go-grpc_out：指定 grpc.pb.go 文件的生成位置  
  
pb/hello.proto：这是指定了 .proto 文件的所在位置  
  
执行上述指令后，会生成 pb.go 和 grpc.pb.go 两个文件.  
```
// ...
package proto


import (
    protoreflect "google.golang.org/protobuf/reflect/protoreflect"
    protoimpl "google.golang.org/protobuf/runtime/protoimpl"
    reflect "reflect"
    sync "sync"
)


// ...
// 请求消息
type HelloReq struct {
    state         protoimpl.MessageState
    sizeCache     protoimpl.SizeCache
    unknownFields protoimpl.UnknownFields
    Name string `protobuf:"bytes,1,opt,name=name,proto3" json:"name,omitempty"`
    Age  int32  `protobuf:"varint,2,opt,name=age,proto3" json:"age,omitempty"`
}


// ...
// 响应消息
type HelloResp struct {
    state         protoimpl.MessageState
    sizeCache     protoimpl.SizeCache
    unknownFields protoimpl.UnknownFields
    
    Reply string `protobuf:"bytes,1,opt,name=reply,proto3" json:"reply,omitempty"`
}
```  
  
   
  
上述代码展示了 pb.go 文件中的内容，核心是基于 .proto 定义的出入参协议，生成对应的 golang 类定义代码.  
###   
```
package proto


import (
    context "context"
    grpc "google.golang.org/grpc"
    codes "google.golang.org/grpc/codes"
    status "google.golang.org/grpc/status"
)


// 基于 .proto 文件生成的客户端框架代码
// 客户端 interface
type HelloServiceClient interface {
    // SayHello 方法
    SayHello(ctx context.Context, in *HelloReq, opts ...grpc.CallOption) (*HelloResp, error)
}


// 客户端实现类
type helloServiceClient struct {
    cc grpc.ClientConnInterface
}


// 客户端构造器函数
func NewHelloServiceClient(cc grpc.ClientConnInterface) HelloServiceClient {
    return &helloServiceClient{cc}
}


// 客户端请求入口
func (c *helloServiceClient) SayHello(ctx context.Context, in *HelloReq, opts ...grpc.CallOption) (*HelloResp, error) {
    out := new(HelloResp)
    err := c.cc.Invoke(ctx, "/pb.HelloService/SayHello", in, out, opts...)
    if err != nil {
        return nil, err
    }
    return out, nil
}


// 服务端注册入口
func RegisterHelloServiceServer(s grpc.ServiceRegistrar, srv HelloServiceServer) {
    s.RegisterService(&HelloService_ServiceDesc, srv)
}


// 服务端业务方法框架代码
func _HelloService_SayHello_Handler(srv interface{}, ctx context.Context, dec func(interface{}) error, interceptor grpc.UnaryServerInterceptor) (interface{}, error) {
    in := new(HelloReq)
    if err := dec(in); err != nil {
        return nil, err
    }
    if interceptor == nil {
        return srv.(HelloServiceServer).SayHello(ctx, in)
    }
    info := &grpc.UnaryServerInfo{
        Server:     srv,
        FullMethod: "/pb.HelloService/SayHello",
    }
    handler := func(ctx context.Context, req interface{}) (interface{}, error) {
        return srv.(HelloServiceServer).SayHello(ctx, req.(*HelloReq))
    }
    return interceptor(ctx, in, info, handler)
}


// 服务端业务处理服务描述符
var HelloService_ServiceDesc = grpc.ServiceDesc{
    ServiceName: "pb.HelloService",
    HandlerType: (*HelloServiceServer)(nil),
    Methods: []grpc.MethodDesc{
        {
            MethodName: "SayHello",
            Handler:    _HelloService_SayHello_Handler,
        },
    },
    Streams:  []grpc.StreamDesc{},
    Metadata: "proto/hello.proto",
}
```  
  
   
  
上述代码展示了 grpc.pb.go 文件中的内容，核心内容包括：  
- • 基于 .proto 文件生成了客户端的桩代码，后续作为用户使用 grpc 客户端模块的 sdk 入口.  
  
   
  
![](https://mmbiz.qpic.cn/mmbiz_png/3ic3aBqT2ibZufUicuib0lkicb5dEuYricbZrkcDurAfUBk8ACXBU94ZmW2u7rEtzgwbN7NrUBO1kx43eUVCo9splV4w/640?wx_fmt=png "")  
  
   
- • 基于 .proto 文件生成了服务端的服务注册桩代码，后续作为用户使用 grpc 服务端模块的 sdk 入口  
  
- • 基于 .proto 文件生成了业务处理服务（pb.HelloService）的描述符，每个描述符内部会建立基于方法名（SayHello）到具体处理函数（_HelloService_SayHello_Handler）的映射关系  
  
   
## 2.3 服务端  
  
服务端启动代码示例如下：  
```
package main


import (
    "context"
    "fmt"
    "net"


    "github.com/grpc_demo/proto"


    "google.golang.org/grpc"
)


// 业务处理服务
type HelloService struct {
    proto.UnimplementedHelloServiceServer
}


// 实现具体的业务方法逻辑
func (s *HelloService) SayHello(ctx context.Context, req *proto.HelloReq) (*proto.HelloResp, error) {
    return &proto.HelloResp{
        Reply: fmt.Sprintf("hello name: %s", req.Name),
    }, nil
}


func main() {
    // 创建 tcp 端口监听器
    listener, err := net.Listen("tcp", ":8093")
    if err != nil {
        panic(err)
    }


    // 创建 grpc server
    server := grpc.NewServer()
    // 将自定义的业务处理服务注册到 grpc server 中
    proto.RegisterHelloServiceServer(server, &HelloService{})
    // 运行 grpc server
    if err := server.Serve(listener); err != nil {
        panic(err)
    }
}
 
```  
  
   
- • 预声明业务处理服务 HelloService，实现好桩文件中定义的业务处理方法 SayHello  
  
- • 调用 net.Listen 方法，创建 tcp 端口监听器  
  
- • 调用 grpc.NewServer 方法，创建一个 grpc server 对象  
  
- • 调用桩文件中预生成好的注册方法 proto.RegisterHelloServiceServer，将 HelloService 注册到 grpc server 对象当中  
  
- • 运行 server.Serve 方法，监听指定的端口，真正启动 grpc server，  
  
   
## 2.4 客户端  
  
客户端启动代码示例如下：  
```
import (
    "context"
    "fmt"


    "github.com/grpc_demo/proto"


    "google.golang.org/grpc"
    "google.golang.org/grpc/credentials/insecure"
)


func main() {
    // 通过指定地址，建立与 grpc 服务端的连接
    conn, err := grpc.Dial("localhost:8093", grpc.WithTransportCredentials(insecure.NewCredentials()))
    // ...
    // 调用 .grpc.pb.go 文件中预生成好的客户端构造器方法，创建 grpc 客户端
    client := proto.NewHelloServiceClient(conn)
  
    // 调用 .grpc.pb.go 文件预生成好的客户端请求方法，使用 .pb.go 文件中预生成好的请求参数作为入参，向 grpc 服务端发起请求
    resp, err := client.SayHello(context.Background(), &proto.HelloReq{
        Name: "xiaoxuxiansheng",
    })
    // ...
    // 打印取得的响应参数
    fmt.Printf("resp: %+v", resp)
}
```  
  
   
  
客户端代码中完成的核心步骤包括：  
- • 调用 grpc.Dial 方法，与指定地址的 grpc 服务端建立连接  
  
- • 调用桩文件中的方法 proto.NewHelloServiceClient，创建 pb 文件预声明好的 grpc 客户端对象  
  
- • 调用 client.SayHello 方法，发送 grpc 请求，并处理响应结果  
  
   
# 3 服务端  
## 3.1 核心数据结构  
  
![](https://mmbiz.qpic.cn/mmbiz_png/3ic3aBqT2ibZufUicuib0lkicb5dEuYricbZrkP5V7PesqjqCM9AljtHtdHBTjQxa14p524d0jia58LFJpjADIR3mozQQ/640?wx_fmt=png "")  
  
   
  
在 grpc 服务端领域，自上而下有着三个层次分明的结构：server->service->method  
- • 最高级别是 server，是对整个 grpc 服务端的抽象  
  
- • 一个 server 下可以注册挂载多个业务服务 service  
  
- • 一个 service 下存在多个业务处理方法 method  
  
   
  
**（1）server**  
```
type Server struct {
    // 配置项
    opts serverOptions
    // 互斥锁保证并发安全
    mu  sync.Mutex 
    // tcp 端口监听器池
    lis map[net.Listener]bool
    // ...
    // 连接池
    conns    map[string]map[transport.ServerTransport]bool
    serve    bool
    cv       *sync.Cond          
    // 业务服务映射管理  
    services map[string]*serviceInfo // service name -> service info
    // ...
    serveWG            sync.WaitGroup 
    // ...
}
```  
  
   
  
Server 类是对 grpc 服务端的代码实现，其中通过一个名为 services 的 map，记录了由服务名到具体业务服务模块的映射关系.  
  
   
  
**（2）serviceInfo**  
```
type serviceInfo struct {
    // 业务服务类
    serviceImpl interface{
    // 业务方法映射管理  
    methods     map[string]*MethodDesc
    // ...
}
```  
  
   
  
serviceInfo 是某一个具体的业务服务模块，其中通过一个名为 methods 的 map 记录了由方法名到具体方法的映射关系.  
  
   
  
**（3）MethodDesc**  
```
type MethodDesc struct {
    MethodName string
    Handler    methodHandler
}
```  
  
   
  
MethodDesc 是对方法的封装，其中的字段 Handler 是真正的业务处理方法.  
  
   
  
**（4）methodHandler**  
```
type methodHandler func(srv interface{}, ctx context.Context, dec func(interface{}) error, interceptor UnaryServerInterceptor) (interface{}, error)
```  
  
   
  
methodsHandler 是业务处理方法的类型，其中几个关键入参的含义分别是：  
- • srv：业务处理方法从属的业务服务模块  
  
- • dec：进行入参 req 反序列化的闭包函数  
  
- • interceptor：业务处理方法外部包裹的拦截器方法  
  
   
## 3.2 创建 server  
```
func NewServer(opt ...ServerOption) *Server {
    opts := defaultServerOptions
    for _, o := range extraServerOptions {
        o.apply(&opts)
    }
    for _, o := range opt {
        o.apply(&opts)
    }
    s := &Server{
        lis:      make(map[net.Listener]bool),
        opts:     opts,
        conns:    make(map[string]map[transport.ServerTransport]bool),
        services: make(map[string]*serviceInfo),
        quit:     grpcsync.NewEvent(),
        done:     grpcsync.NewEvent(),
        czData:   new(channelzData),
    }
    chainUnaryServerInterceptors(s)
    //...
    s.cv = sync.NewCond(&s.mu)
    // ...   
    return s
}
```  
  
   
  
grpc.NewServer 方法中会创建 server 实例，并调用 chainUnaryServerInterceptors 方法，将一系列拦截器 interceptor 成链，并注入到 ServerOption 当中. 有关拦截器的内容，放在本文第 4 章再作展开.  
```
func chainUnaryServerInterceptors(s *Server) {


    interceptors := s.opts.chainUnaryInts
    if s.opts.unaryInt != nil {
        interceptors = append([]UnaryServerInterceptor{s.opts.unaryInt}, s.opts.chainUnaryInts...)
    }


    var chainedInt UnaryServerInterceptor
    if len(interceptors) == 0 {
        chainedInt = nil
    } else if len(interceptors) == 1 {
        chainedInt = interceptors[0]
    } else {
        chainedInt = chainUnaryInterceptors(interceptors)
    }
    
    s.opts.unaryInt = chainedInt
}
```  
  
   
## 3.3 注册 service  
  
![](https://mmbiz.qpic.cn/mmbiz_png/3ic3aBqT2ibZufUicuib0lkicb5dEuYricbZrklRhhqZbXweHdgsiaX7Kd45OerRf6odrd6H1iaeC1BTAODicrvoMLMO4VA/640?wx_fmt=png "")  
  
   
  
创建好 grpc server 后，接下来通过使用桩代码中预生成好的 RegisterXXXServer 方法，业务处理服务 service 模块注入到 server 当中.  
```
func RegisterHelloServiceServer(s grpc.ServiceRegistrar, srv HelloServiceServer) {
    s.RegisterService(&HelloService_ServiceDesc, srv)
}
```  
  
   
```
func (s *Server) RegisterService(sd *ServiceDesc, ss interface{}) {
    // ...
    s.register(sd, ss)
}
```  
  
   
```
func (s *Server) register(sd *ServiceDesc, ss interface{}) {
    s.mu.Lock()
    defer s.mu.Unlock()
    // ...
    info := &serviceInfo{
        serviceImpl: ss,
        methods:     make(map[string]*MethodDesc),
        streams:     make(map[string]*StreamDesc),
        mdata:       sd.Metadata,
    }
    for i := range sd.Methods {
        d := &sd.Methods[i]
        info.methods[d.MethodName] = d
    }
    // ...
    s.services[sd.ServiceName] = info
}
```  
  
   
  
注册过程会经历 RegisterHelloServiceServer->Server.RegisterService -> Server.register 的调用链路，把 service 的所有方法注册到 serviceInfo 的 methods map 当中，然后将 service 封装到 serviceInfo 实例中，注册到 server 的 services map 当中  
  
   
## 3.4 运行 server  
```
func (s *Server) Serve(lis net.Listener) error {
    // ...


    var tempDelay time.Duration // how long to sleep on accept failure
    for {
        rawConn, err := lis.Accept()
        if err != nil {
            // ...
        }
        // ...
        s.serveWG.Add(1)
        go func() {
            s.handleRawConn(lis.Addr().String(), rawConn)
            s.serveWG.Done()
        }()
    }
}
```  
  
   
  
![](https://mmbiz.qpic.cn/mmbiz_png/3ic3aBqT2ibZufUicuib0lkicb5dEuYricbZrkHVhQdZxaNNeM38wT2H7oMkdFYfXhDswNicrqVRTTRr23tK2ia5JyljlA/640?wx_fmt=png "")  
  
grpc server 运行的流程，核心是基于 for 循环实现的主动轮询模型，每轮会通过调用 net.Listener.Accept 方法，基于 IO 多路复用 epoll 方式，阻塞等待 grpc 请求的到达.  
  
每当有新的连接到达后，服务端会开启一个 goroutine，调用对应的 Server.handleRawConn 方法对请求进行处理.  
  
   
## 3.5 处理请求  
```
func (s *Server) handleRawConn(lisAddr string, rawConn net.Conn) {
    // ...
    st := s.newHTTP2Transport(rawConn)
    // ...
    go func() {
        s.serveStreams(st)
        s.removeConn(lisAddr, st)
    }()
}
```  
  
   
  
![](https://mmbiz.qpic.cn/mmbiz_png/3ic3aBqT2ibZufUicuib0lkicb5dEuYricbZrkPBwMG29NaFfabCic8PiclMc6gWgqyvFN1j2Y2hdQVaFw8COt7rbEN1EA/640?wx_fmt=png "")  
  
在 Server.handleRawConn 方法中，会基于原始的 net.Conn 封装生成一个 HTTP2Transport，然后开启 goroutine 调用 Server.serveStream 方法处理请求.  
  
   
```
func (s *Server) serveStreams(st transport.ServerTransport) {
    var wg sync.WaitGroup


    var roundRobinCounter uint32
    st.HandleStreams(func(stream *transport.Stream) {
        go func() {
            defer wg.Done()
            s.handleStream(st, stream, s.traceInfo(st, stream))
        }()
    }, func(ctx context.Context, method string) context.Context {
        // ...
    })
    wg.Wait()
}
```  
  
   
```
func (s *Server) handleStream(t transport.ServerTransport, stream *transport.Stream, trInfo *traceInfo) {
    sm := stream.Method()
    // ...
    pos := strings.LastIndex(sm, "/")
    
    service := sm[:pos]
    method := sm[pos+1:]


    srv, knownService := s.services[service]
    if knownService {
        if md, ok := srv.methods[method]; ok {
            s.processUnaryRPC(t, stream, srv, md, trInfo)
            return
        }
        if sd, ok := srv.streams[method]; ok {
            s.processStreamingRPC(t, stream, srv, sd, trInfo)
            return
        }
    }
    // ...
}
```  
  
   
```
func (s *Server) processUnaryRPC(t transport.ServerTransport, stream *transport.Stream, info *serviceInfo, md *MethodDesc, trInfo *traceInfo) (err error) {
    // ...
    d, err := recvAndDecompress(&parser{r: stream}, stream, dc, s.opts.maxReceiveMessageSize, payInfo, decomp)
    // ...
    df := func(v interface{}) error {
        if err := s.getCodec(stream.ContentSubtype()).Unmarshal(d, v); err != nil {
           // ...
        }
        // ...
    }
    ctx := NewContextWithServerTransportStream(stream.Context(), stream)
    reply, appErr := md.Handler(info.serviceImpl, ctx, df, s.opts.unaryInt)
    // ...


    if err := s.sendResponse(t, stream, reply, cp, opts, comp); err != nil {
        // ...
    }
    // ...
}
```  
  
   
  
![](https://mmbiz.qpic.cn/mmbiz_png/3ic3aBqT2ibZufUicuib0lkicb5dEuYricbZrkgeibXoaznl3ZDlYGicPP7h90O1DB1Rxxw3Zick9CN6wOJBVlwhekV7BFw/640?wx_fmt=png "")  
  
   
  
接下来一连建立了 Server.serveStreams -> http2Server.HandleStreams -> http2Server.operateHeaders -> http2Server.handleStream -> Server.processUnaryRPC 的方法调用链：  
- • 在 Server.handleStream 方法中，会拆解来自客户端的请求路径 ${service}/${method}，通过"/" 前段得到 service 名称，通过 "/" 后端得到 method 名称，并分别映射到对应的业务服务和业务方法  
  
- • 在 Server.processUnaryRPC 方法中，会通过 recvAndDecompress 读取到请求内容字节流，然后通过闭包函数 df 封装好反序列请求参数的逻辑，继而调用 md.Handler 方法处理请求，最终通过 Server.sendResponse 方法将响应结果进行返回  
  
   
```
func _HelloService_SayHello_Handler(srv interface{}, ctx context.Context, dec func(interface{}) error, interceptor grpc.UnaryServerInterceptor) (interface{}, error) {
    in := new(HelloReq)
    if err := dec(in); err != nil {
        return nil, err
    }
    if interceptor == nil {
        return srv.(HelloServiceServer).SayHello(ctx, in)
    }
    info := &grpc.UnaryServerInfo{
        Server:     srv,
        FullMethod: "/pb.HelloService/SayHello",
    }
    handler := func(ctx context.Context, req interface{}) (interface{}, error) {
        return srv.(HelloServiceServer).SayHello(ctx, req.(*HelloReq))
    }
    return interceptor(ctx, in, info, handler)
}
```  
  
   
  
以本文介绍的 helloService 为例，客户端调用 SayHello 方法后，服务端对应的 md.Handler 正是 .proto 文件生成的位于 .grpc.pb.go 文件中的桩方法 _HelloService_SayHello_Handler.  
  
在该桩方法内部中，包含的执行步骤如下：  
- • 调用闭包函数 dec，将请求内容反序列化到请求入参 in 当中  
  
- • 将业务处理方法 HelloServiceServer.SayHello 闭包封装到一个 UnaryHandler 当中  
  
- • 调用 intercetor 方法，分别执行拦截器和 handler 的处理逻辑  
  
   
# 4 拦截器  
  
有关 grpc 中拦截器 interceptor 部分的内容理解起来比较费脑，我们单开一章来展开聊聊.  
## 4.1 原理介绍  
  
拦截器的作用，是在执行核心业务方法的前后，创造出一个统一的切片，来执行所有业务方法锁共有的通用逻辑. 此外，我们还能够通过这部分通用逻辑的执行结果，来判断是否需要熔断当前的执行链路，以起到所谓的”拦截“效果.  
  
有关 grpc 拦截器的内容，其实和 gin 框架中的 handlersChain 是异曲同工的. 在我之前分享的文章 ”解析 Gin 框架底层原理“ 的第 5 章内容中有作详细介绍，大家不妨引用对比，以此来触类旁通，加深理解.  
  
   
  
下面我们看看 grpc 中对于一个拦截器函数的具体定义：  
```
type UnaryServerInterceptor func(ctx context.Context, req interface{}, info *UnaryServerInfo, handler UnaryHandler) (resp interface{}, err error)
```  
  
其中几个入参的含义分别为：  
- • req：业务处理方法的请求参数  
  
- • info：当前所属的业务服务 service  
  
- • handler：真正的业务处理方法  
  
   
  
因此一个拦截器函数的使用模式应该是：  
```
var myInterceptor1 = func(ctx context.Context, req interface{}, info *grpc.UnaryServerInfo, handler grpc.UnaryHandler) (resp interface{}, err error) {
    // 前处理校验
    if err := preLogicCheck();err != nil{
       // 前处理校验不通过，则拦截，不调用业务方法直接返回
       return nil,err 
    }
    
     // 前处理校验通过，正常调用业务方法
     resp, err = handle(ctx,req)
     if err != nil{
         return nil,err 
     }
     
      // 后置处理校验
      if err := postLogicCheck();err != nil{
         // 后置处理校验不通过，则拦截结果，包装错误返回
         return nil,err 
      }
      
      // 正常返回结果
      return resp,nil 
}
```  
  
   
## 4.2 拦截器链  
  
![](https://mmbiz.qpic.cn/mmbiz_png/3ic3aBqT2ibZufUicuib0lkicb5dEuYricbZrkCSY18OuicMq5zB97FPT7a2mWicIUjINz0Fd0jiaibYmp7aqMA7icBDPqCQQ/640?wx_fmt=png "")  
```
func chainUnaryInterceptors(interceptors []UnaryServerInterceptor) UnaryServerInterceptor {
    return func(ctx context.Context, req interface{}, info *UnaryServerInfo, handler UnaryHandler) (interface{}, error) {
        return interceptors[0](ctx, req, info, getChainUnaryHandler(interceptors, 0, info, handler))
    }
}


func getChainUnaryHandler(interceptors []UnaryServerInterceptor, curr int, info *UnaryServerInfo, finalHandler UnaryHandler) UnaryHandler {
    if curr == len(interceptors)-1 {
        return finalHandler
    }
    return func(ctx context.Context, req interface{}) (interface{}, error) {
        return interceptors[curr+1](ctx, req, info, getChainUnaryHandler(interceptors, curr+1, info, finalHandler))
    }
}
```  
  
首先，chainUnaryInterceptors 方法会将一系列拦截器 interceptor 成链，并返回首枚interceptor 供 ServerOption 接收设置.  
  
其中，拦截器成链的关键在于 getChainUnaryHandler 方法中，其中会闭包调用拦截器数组的首枚拦截器函数，接下来依次用下一枚拦截器对业务方法 handler 进行包裹，封装成一个新的 ”handler“ 供当前拦截器使用.  
  
   
  
![](https://mmbiz.qpic.cn/mmbiz_png/3ic3aBqT2ibZufUicuib0lkicb5dEuYricbZrkKibgSicr1UXCU6Hbn3uofCakZiceibXk8ib8HMtiarzoxPoH2Btt9Yy0ibqVw/640?wx_fmt=png "")  
  
   
  
   
## 4.3 操作实践  
  
下面展示一下 grpc 拦截器链的实操例子.  
- • 依次声明拦截器1 myInterceptor1 和 拦截器2 myInterceptor2，会在调用业务方法 handler 前后分别打印一行内容  
  
- • 在创建 grpc server 时，将两个拦截器基于 option 注入  
  
- • 通过客户端请求服务端，通过输出日志观察拦截器运行效果  
  
```
var myInterceptor1 = func(ctx context.Context, req interface{}, info *grpc.UnaryServerInfo, handler grpc.UnaryHandler) (resp interface{}, err error) {
    fmt.Printf("interceptor1 preprocess, req: %+v\n", req)
    resp, err = handler(ctx, req)
    fmt.Printf("interceptor1 postprocess, req: %+v\n", resp)
    return
}


var myInterceptor2 = func(ctx context.Context, req interface{}, info *grpc.UnaryServerInfo, handler grpc.UnaryHandler) (resp interface{}, err error) {
    fmt.Printf("interceptor2 preprocess, req: %+v\n", req)
    resp, err = handler(ctx, req)
    fmt.Printf("interceptor2 postprocess, resp: %+v\n", resp)
    return
}


func (s *Server) SayHello(ctx context.Context, req *proto.HelloReq) (*proto.HelloResp, error) {
    fmt.Println("core handle logic......")
    return &proto.HelloResp{
        Reply: fmt.Sprintf("hello name: %s", req.Name),
    }, nil
}


func main() {
    listener, err := net.Listen("tcp", ":8093")
    if err != nil {
        panic(err)
    }


    server := grpc.NewServer(grpc.ChainUnaryInterceptor(myInterceptor1, myInterceptor2))
    proto.RegisterHelloServiceServer(server, &Server{})


    if err := server.Serve(listener); err != nil {
        panic(err)
    }
}
```  
  
   
  
   
  
![](https://mmbiz.qpic.cn/mmbiz_png/3ic3aBqT2ibZufUicuib0lkicb5dEuYricbZrkI3NlbqEhzbLiaZMJBJnpDwGQibBRGn1tGvib60AehAEObfy7qmcD7KKNA/640?wx_fmt=png "")  
  
   
# 5 展望  
  
本文向大家引入了 grpc-go 框架，介绍了其基本用法，和大家一起梳理了服务端运行的核心方法链路. 实际上，本文内容仅仅是 grpc 领域中的冰山一角，更多细节如序列化协议、服务注册/发现、负载均衡等内容，留待后续的篇章和大家再作分享探讨.  
  
  
