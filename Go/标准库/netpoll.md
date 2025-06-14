#toread
#  万字解析 golang netpoll 底层原理  
原创 小徐先生1212  小徐先生的编程世界   2024-09-21 22:57  
  
# 0 前言  
  
在 23年初，我曾发表过一篇文章——[解析 golang 网络 io 模型之 epoll](http://mp.weixin.qq.com/s?__biz=MzkxMjQzMjA0OQ==&mid=2247484057&idx=1&sn=50e57108f736bc47137ac57dfb643893&chksm=c10c4c47f67bc551462c64bd58378589814772f2c8e6a40a5970c13d838f2af1ccb2763df259&scene=21#wechat_redirect)  
. 当时以源码走读的方式，和大家一起粗略探讨了有关 golang 底层如何基于 epoll 实现 io 模型的问题.  
  
然而，当时的我存在视野局限的问题，由于仅接触过 golang 一门语言，所谓只见树木不见森林，在学习 golang 底层知识时总是理所当然地接受这是所谓的标准答案，而对其中一些方案的选型思辨和技术细节总是欠缺主动思考.  
  
随着最近开始学习 C++ 并尝试理解和实践 io 相关模块，我不免拿出 golang 实现方案进行比较借鉴，发现通过这种不同语言生态之间的横向对比，进一步对 golang io 底层模型的策略取舍产生了一些新的感悟，于是以此为契机，我将在近期开启一个新的专题，其中会包含如下三篇内容：  
- • 第一篇——万字解析 golang netpoll 底层原理：这是一个力求温故而知新的重置篇章，希望在有了不同语言间横向对比的视角后，能够对 golang 底层 io 模型设计、方案取舍原因有着更加立体的认知. 在本文中，我们将涉及到的如下知识点：io多路复用概念、epoll实现原理、针对 golang 底层 epoll 应用细节以及 netpoll 框架模型进行源码级别的讲解.  
  
- • 第二篇——C++ 从零实现 epoll server：作为个人自学 C++ 过程中的练手项目，将从一线视角出发，揭示有关 socket 编程、epoll 指令、io 模型的实现细节，基于 C++ 从零到一搭建出一个开源 tcp server library.  
  
- • 第三篇——C++ 从零实现 http server：在 epoll server 基础上完善有关 http 协议解析和路由管理的功能，实现能一键启动、开箱即用的 http server library.  
# 1 基础理论铺垫  
  
## 1.1 io 多路复用  
  
在正式开始，我们有必要作个预热，提前理解一下所谓io多路复用的概念.  
  
拆解多路复用一词，所谓多路，指的是存在多个待服务目标，而复用，指的是重复利用一个单元来为上述的多个目标提供服务.  
> 聊到io多路复用时，我比较希望举一个经营餐厅的例子——一个餐馆在运营过程中，考虑到人力成本，一个服务员往往需要同时为多名不同的顾客提供服务，这个服务过程本质上就属于多路复用.  
  
  
![](https://mmbiz.qpic.cn/sz_mmbiz_png/3ic3aBqT2ibZv1CgmoR8HX3RbUKBzMTicDRjlo0cIlxF54xAW3ucdKAPpkkjXgGjXah2NYVF8XzOvxVsJfpopgvGQ/640?wx_fmt=png&from=appmsg "")  
  
下面我们就以这个餐厅的例子作为辅助，来一起从零到一地推演一遍 io 多路复用技术的形成思路.  
  
**1）单点阻塞 io 模型**  
  
在 linux 系统中，一切皆为文件，即一切事物都可以抽象化为一个文件句柄 file descriptor，后续简称 fd.  
  
比如服务端希望接收来自客户端的连接，其中一个实现方式就是让线程 thread 以阻塞模式对 socket fd 发起 accept 系统调用，这样当有连接到达时，thread 即可获取结果；当没有连接就绪事件时，thread 则会因 accept 操作而陷入阻塞态.  
  
![](https://mmbiz.qpic.cn/sz_mmbiz_png/3ic3aBqT2ibZv1CgmoR8HX3RbUKBzMTicDRCu03iabJptwMyNUiclSYP5a5cE43FFuq2AnHXf2S5we7FLCPJMwCuWdQ/640?wx_fmt=png&from=appmsg "")  
  
这样阻塞模式的好处就在于，thread 可以在所依赖事件未就绪时，通过阻塞的模式让渡出 cpu 执行权，在后续条件就绪时再被唤醒，这样就能做到忙闲有度，提高 cpu 的利用率.  
> 这样表述完，大家未必能直接感受到该方式存在的局限，我们将其翻译成餐厅的例子——这就好比是餐厅为每名顾客提供一位专属服务员进行一对一服务的（单点），专属服务员只关注特定顾客的指令，在此之前完全处于沉默待命状态（阻塞态），对其他客人的传唤也是充耳不闻.  
  
  
而上述方式存在的不足之处就在于人力成本. 我们一名服务员只能为一名顾客提供服务，做不到复用，显得有点儿浪费. 于是接下来演进的方向所需要围绕的目标就是——降本增效.  
  
**2）多点轮询 + 非阻塞io 模型**  
  
要复用，就得做到让一个 thread 能同时监听多个 fd，只要任意其一有就绪事件到达，就能被 thread 接收处理. 在此前提下，accept 的阻塞调用模式就需要被摒弃，否则一旦某个 fd 连接未就绪时，thread 就会立刻被 block 住，而无法兼顾到其他 fd 的情况.  
  
于是我们可以令 thread 采用非阻塞轮询的方式，一一对每个 fd 执行非阻塞模式下的 accept 指令：此时倘若有就绪的连接，就能立即获得并做处理；若没有就绪事件，accept 也会立刻返回错误结果（EAGAIN） ，thread 可以选择忽略跳过，并立即开始下一次轮询行为.  
  
![](https://mmbiz.qpic.cn/sz_mmbiz_png/3ic3aBqT2ibZv1CgmoR8HX3RbUKBzMTicDRyq1hSSvqicdnB1SwNkhdELG6F5icnWjibYo5hseFJYzNcGJ1cLGV1rdhw/640?wx_fmt=png&from=appmsg "")  
  
上述方式倒是实现复用了，但其背后存在什么问题呢？  
> 同样用餐厅的例子加以说明. 餐厅规定一个服务员需要同时为多名指定的顾客提供服务，但这名服务员需要辗转腾挪各餐桌之间，轮流不间断地对每名客人进行主动问询，即便得到回复基本都是否定的，但他也一刻都不允许停歇. 这样的操作模式下，即使客人不嫌烦，这个服务员自己也会被这种高强度的无效互动行为给折腾到筋疲力尽.  
  
  
相信这样解释完，大家也能看出问题所在. 在这种模式下，thread 不间断地在对每个 fd 发起非阻塞系统调用，倘若各 fd 都没有就绪事件，那么 thread 就只会一直持续着无意义的空转行为，这无疑是一种对 cpu 资源的浪费.  
  
**3）io 多路复用**  
  
到了这里，大家可能就会问了，餐厅能否人性化一些，虽然我们希望让服务生与顾客之间建立一对多的服务关系，但是服务生可以基于顾客的主动招呼再采取响应，而在客人没有明确诉求时，服务生可以小憩一会儿，一方面养足体力，另一方面也避免对客人产生打扰.  
> 是的，这个解决方案听起来似乎是顺理成章的，然而放到计算机领域可能就并非如此了. 用户态 thread 是一名视听能力不好的服务生，他无法同时精确接收到多名顾客的主动传唤，只能通过一一向顾客问询的方式（系统调用）来获取信息，这就是用户态视角的局限性.  
  
  
于是为了解决上述问题，io 多路复用技术就应运而生了. 它能在单个指令层面支持让用户态 thread 同时对多个 fd 发起监听，调用模式还可以根据使用需要调整为非阻塞、阻塞或超时模式.  
  
![](https://mmbiz.qpic.cn/sz_mmbiz_png/3ic3aBqT2ibZv1CgmoR8HX3RbUKBzMTicDRKHG7Sp4akCgbXbES3Yx1P5Jb4SerPlC0vGWlS5ALywrEpULITybXnA/640?wx_fmt=png&from=appmsg "")  
  
在 linux 系统中，io 多路复用技术包括 select、poll、epoll. 在随后的章节中我们将重点针对 epoll 展开介绍，并进一步揭示 golang io 模型底层对 epoll 的应用及改造.  
## 1.2 epoll 核心知识  
  
epoll 全称 EventPoll，顾名思义，是一种以事件回调机制实现的 io 多路复用技术.  
  
epoll 是一个指令组，其中包含三个指令：  
- • epoll_create；  
  
- • epoll_ctl；  
  
- • epoll_wait.  
  
以上述三个指令作为主线，我们通过流程串联的方式来揭示 epoll 底层实现原理.  
  
**1）epoll_create**  
```
extern int epoll_create (int __size) __THROW;
```  
  
通过 epoll_create 可以开辟一片内核空间用于承载 epoll 事件表，在表中可以注册一系列关心的 fd 、相应的监听事件类型以及回调时需要携带的数据.  
  
epoll 事件表是基于红黑树实现的 key-value 有序表，其中 key 是 fd，value 是监听事件类型以及使用方自定义拓展数据.  
  
![](https://mmbiz.qpic.cn/sz_mmbiz_png/3ic3aBqT2ibZv1CgmoR8HX3RbUKBzMTicDRztJ3iaCiaIVQ75p9nfhAft6AH3WzmXjaCgXrWroQibI66eIlcI1ugzT7Q/640?wx_fmt=png&from=appmsg "")  
> 针对 epoll 事件表的数据结构选型，可能部分同学会在心中存有疑惑——为什么不基于哈希表而选择了红黑树这种有序表结构呢？针对该问题，我在此仅提供一些个人观点：  
> • 内存连续性：哈希表底层基于桶数组 + 链表实现时，桶数组部分在存储上需要为连续空间；而红黑树节点之间通过链表指针关联，可以是非连续空间，在空间分配上比较灵活• 操作性能：虽然哈希表的时间复杂度是 O(1)，但是常数系数很高；而红黑树虽为 O(logN)，但在 N 不大的情况下（fd数量相对收敛），O(logN) 相对于O（1）差距并不大，此时哈希表的高常数系数反而会导致性能瓶颈  
  
  
**2）epoll_ctl**  
  
epoll_ctl 指令用于对 epoll 事件表内的 fd 执行变更操作，进一可分为：  
- • EPOLL_CTL_ADD：增加 fd 并注册监听事件类型  
  
- • EPOLL_CTL_MOD：修改 fd 监听事件类型  
  
- • EPOLL_CTL_DEL：删除 fd  
  
```
extern int epoll_ctl (int __epfd, int __op, int __fd,              struct epoll_event *__event) __THROW;
```  
  
由于 epoll 事件表是红黑树结构，所以上述操作时间复杂度都是 O(logN) 级别  
  
![](https://mmbiz.qpic.cn/sz_mmbiz_png/3ic3aBqT2ibZv1CgmoR8HX3RbUKBzMTicDRhkQ8C4E4n83U5DVmMnQAypGxvm5eSxCo9OWFGsR7niaeFkVF6mam6Ag/640?wx_fmt=png&from=appmsg "")  
  
**3）epoll_wait**  
  
执行 epoll_wait 操作时，会传入一个固定容量的就绪事件列表，当注册监听的 io 事件就绪时，内核中会基于事件回调机制将其添加到就绪事件列表中并进行返回.  
  
值得一提的是epoll_wait 操作还能够支持非阻塞模式、阻塞模式以及超时模式的多种调用方式.  
```
extern int epoll_wait (int __epfd, struct epoll_event *__events,               int __maxevents, int __timeout);
```  
  
![](https://mmbiz.qpic.cn/sz_mmbiz_png/3ic3aBqT2ibZv1CgmoR8HX3RbUKBzMTicDRLqqicSkeL5wSsoWdpKBKUbUFDybHbQic9s9lqjT8NjkAbQBKjMy3ibTIA/640?wx_fmt=png&from=appmsg "")  
  
我们回头总结一下epoll 中存在的优势，这里主要与 select 指令进行对比（本文中没有对 select 展开介绍，这部分需要大家自行了解）：  
- • fd数量灵活：epoll 事件表中 fd 数量上限灵活，由使用方在调用 epoll_create 操作时自行指定（而 select 可支持的fd 数量固定，灵活度不足）  
  
- • 减少内核拷贝：epoll_create 指令开辟内核空间后，epoll_ctl 注册到事件表中的 fd 能够多次 epoll_wait 操作复用，不需要重复执行将 fd 从用户态拷贝到内核态的操作（select 操作是一次性的，每起一轮操作都需要重新指定 fd 并将其拷贝到内核中）  
  
- • 返回结果明确：epoll_wait 直接将明确的就绪事件填充到使用方传入的就绪事件列表中，节省了使用方的检索成本（select 只返回就绪事件数量而不明确告知具体是哪些 fd 就绪，使用方还存在一次额外的检索判断成本）  
  
> 凡事都需要辩证看待，在不同的条件与语境下，优劣势的地位可能会发生转换. 以 epoll 而言，其主要适用在监听 fd 基数较大且活跃度不高的场景，这样 epoll 事件表的空间复用以及epoll_wait操作的精准返回才能体现出其优势 ；反之，如果 fd数量不大且比较活跃时，反而适合 select 这样的简单指令，此时 epoll核心优势体现不充分，其底层红黑树这样的复杂结构实现反而徒增累赘.  
  
# 2 go netpoll 原理  
## 2.1 整体架构设计  
  
在 linux 系统下，golang 底层依赖 epoll 作为核心基建来实现其 io 模型，但在此基础上，golang还设计了一套因地制宜的适配方案，通常被称作 golang netpoll 框架.  
  
![](https://mmbiz.qpic.cn/sz_mmbiz_png/3ic3aBqT2ibZv1CgmoR8HX3RbUKBzMTicDRGqiaiabFgZRG1UOF49ficjchibWROzbjV9ibXSSP1PmzwccCiaVrFScNun2Q/640?wx_fmt=png&from=appmsg "")  
  
下面我们从流程拆解的方式，来对 netpoll 框架展开介绍：  
- • poll_init：底层调用 epoll_create 指令，完成epoll 事件表的初始化（golang 进程中，通过 sync.Once保证 poll init 流程只会执行一次. ）  
  
- • poll_open：首先构造与 fd 对应的 pollDesc实例，其中含有事件状态标识器 rg/wg，用于标识事件状态以及存储因poll_wait 而阻塞的 goutine（简称 g） 实例；接下来通过 epoll_ctl（ADD）操作，将 fd（key） 与 pollDesc（value） 注册到 epoll事件表中  
  
- • poll_close：执行 epoll_ctl（DEL）操作，将 pollDesc 对应 fd 从 epoll 事件表中移除  
  
- • poll_wait：当 g 依赖的某io 事件未就绪时，会通过 gopark 操作，将 g 置为阻塞态，并将 g 实例存放在 pollDesc 的事件状态标识器 rg/wg 中  
  
- • net_poll：gmp 调度流程会轮询驱动 netpoll 流程，通常以非阻塞模式发起 epoll_wait 指令，取出所有就绪的 pollDesc，通过事件标识器取得此前因 gopark 操作而陷入阻塞态的 g，返回给上游用于唤醒和调度（事实上，在 gc（垃圾回收 garbage collection） 和 sysmon 流程中也存在触发 netpoll 流程的入口，但属于支线内容，放在 3.8 小节中展开）  
  
## 2.2 net server 流程设计  
  
以启动 net server 的流程为例，来观察其底层与 netpoll 流程的依赖关系：  
  
![](https://mmbiz.qpic.cn/sz_mmbiz_png/3ic3aBqT2ibZv1CgmoR8HX3RbUKBzMTicDRiacdFwicYLWaSEopI1vyfX2nNPy5l5gBOIUo2lk2k4UQTScBv8yz8zZQ/640?wx_fmt=png&from=appmsg "")  
- • net.listen：启动 server 前，通过 net.Listen 方法创建端口监听器 listener. 具体包括如下几个核心步骤：  
  
- • 创建 socket：通过 syscall socket 创建 socket fd，并执行 bind、listen 操作，完成 fd 与端口的绑定以及开启监听  
  
- • 执行 poll init 流程：通过 epoll create 操作创建 epoll 事件表  
  
- • 执行 poll open流程：将端口对应的 socket fd 通过 epoll ctl（ADD）操作注册到 epoll 事件表中，监听连接就绪事件  
  
- • listener.Accept：创建好 listener 后，通过 listener.Accept 接收到来的连接：  
  
- • 轮询 + 非阻塞 accept：轮询对 socket fd 调用非阻塞模式下的 accept 操作，获取到来的连接  
  
- • 执行 poll wait 流程：如若连接未就绪，通过 gopark 操作将当前 g 阻塞，并挂载在 socket fd 对应 pollDesc 的读事件状态标识器 rg 中  
  
- • 执行 poll open 流程：如若连接已到达，将 conn fd 通过 epoll ctl（ADD）操作注册到 epoll 事件表中，监听其读写就绪事件  
  
- • conn.Read/Write：通过 conn.Read/Write 方法实现数据的接收与传输  
  
- • 轮询 + 非阻塞 read/write：轮询以非阻塞模式对 conn fd 执行 read/write 操作，完成数据接收与传输  
  
- • 执行 poll wait 流程：如果 conn fd 的读写条件未就绪，通过 gopark 操作将当前 goroutine 阻塞，并挂载在 conn fd 对应 pollDesc 的读/写事件标识器 rg/wg 中  
  
- • conn.Close：当连接已处理完毕时，通过 conn.Close 方法完成连接关闭，实现资源回收  
  
- • 执行 poll close 流程：通过 epoll ctl（DEL）操作，将 conn fd 从 epoll 事件表中移除  
  
- • close fd：通过 close 操作，关闭回收 conn 对应 fd 句柄  
  
## 2.3 因地制宜的策略选型  
  
我在学习初始阶段，常常对 golang netpoll 中的 poll_wait 流程和 epoll_wait 流程产生定位混淆，事实上两者是完全独立的流程.  
  
在 golang 的 poll_wait 流程中，并没有直接调用到 epoll_wait，而是通过 gopark 操作实现将当前 g 只为阻塞态的操作；而真正调用 epoll_wait 操作是 gmp 轮询调用的 netpoll 流程中，并通常是以非阻塞模式来执行 epoll_wait 指令，在找到就绪的 pollDesc 后，进一步获取其中存储的g 实例，最后通过 goready 操作来唤醒 g.  
  
上述在阻塞方式实现上的差异，正是golang netpoll 在 epoll 基础上所作出的最核心的改造项. 在这里，可能有部分同学可能会产生疑惑，为什么 golang 不利用阻塞模式的epoll_wait 指令来直接控制 g 的阻塞与唤醒呢？  
  
这个问题的答案就是——epoll_wait 做不到. epoll_wait 的调用单元是 thread，及 gmp 中的 m，而非 g. 而我们都知道 golang 是门天然支持高并发的语言，它通过一套 gmp 架构，为使用方屏蔽了有关线程 thread 的所有细节，保证语言层面的并发粒度都控制在更精细的 g 之上. 因此在 golang io 模型的设计实现中，需要尽可能避免 thread 级别的阻塞，因此当 g 因 io 未就绪而需要阻塞时，应该通过 gopark 实现用户态下 g 粒度的阻塞，而非简单地基于阻塞模式进行 epoll_wait 指令的调用.  
  
建构了上述这一点认知后，大家再回头梳理一遍有关 golang poll_wait 和 net_poll 流程的设计思路，相信大家就能够释然了.  
  
![](https://mmbiz.qpic.cn/sz_mmbiz_png/3ic3aBqT2ibZv1CgmoR8HX3RbUKBzMTicDRIQJHjd0MIrOuRRmJKDxJJHNBRhdw0tF250m7tynd4XljtQoeVTZ0UQ/640?wx_fmt=png&from=appmsg "")  
  
然而，到这里为止，可能有部分同学又会产生疑问了——在本文 1.1 小节推演 io 多路复用模型时提过，这种轮询 + 非阻塞 io 的调用模式是存在缺陷的，问题就在于轮询单元可能因 io 事件未就绪而持续无意义的空转，最终导致 cpu 资源的浪费.  
> 哈哈上述问题也许只是我个人一厢情愿的自说自话，但若确实有同学有在此处抛出和我一样的问题，那请在此接收我的夸奖，你的思维很 nice，这是一个很好的问题，保持辩证思维是我们在求学一门新知识时应该持有的良好态度.  
  
  
正如 2.1 小节中所说，驱动 net_poll 流程的时机主要发生在 gmp 调度流程中，因此这个问题的答案是和 gmp 底层原理息息相关的：  
  
● 一方面，p 本就是基于轮询模型不断寻找合适的 g 进行调度，而 net_poll 恰好是其寻找 g 的诸多方式的其中一种，因此这个轮询机制是与 gmp 天然契合的，并非是 golang netpoll 机制额外产生的成本；  
  
● 再者，这种轮询不是墨守成规，而是随机应变的. 如果一个 p 经历了一系列检索操作后，仍找不到合适的 g 进行调度，那么它不会无限空转，而是会适时地进行缩容操作——首先保证全局会留下一个 p 进行 netpoll 留守，其会通过阻塞或超时模式触发执行 epoll_wait 操作，保证有 io 事件就绪时不产生延迟（具体细节参见 3.8 小节）；而在有留守 p 后，其它空闲的 p 会将 m 和 p 自身都置为 idle 态，让出 cpu 执行权，等待后续有新的 g 产生时再被重新唤醒  
  
gmp 是整个 golang 知识体系的基石，我也在23年初也曾写过一篇——[Golang GMP 原理](http://mp.weixin.qq.com/s?__biz=MzkxMjQzMjA0OQ==&mid=2247483889&idx=1&sn=dd5066f7c27a6b29f57ff9fecb699d77&chksm=c10c4f2ff67bc6399089e3decbec04418e5c89626d919c4a42bde26c761ad19e2c683a26445b&scene=21#wechat_redirect)  
，不过当时同样存在视野局限问题，理解广度与深度都有所不足，所以这里也留个预告彩蛋，很快我将会针对 gmp 重启一个篇章进行查缺补漏，争取做到温故知新.  
# 3 go netpoll 源码  
  
下面我们围绕着第 2 章中介绍的内容，开启大家最喜闻乐见的源码走读环节.  
  
此处使用的 golang 源码版本为 v1.19.3，操作系统为 linux 系统，netpoll 底层基于 epoll 技术实现.  
## 3.1 核心流程入口  
  
这里给出简易版 tcp 服务器框架的实现示例，麻雀虽小五脏俱全，其中包含了 2.2 小节中介绍到的有关net server 几大核心流程相关的代码入口：  
```
// 启动 tcp server 代码示例
func main(){
    /*        - 创建 tcp 端口监听器            - 创建 socket fd，bind、accept            - 创建 epoll 事件表（epoll_create）            - socket fd 注册到 epoll 事件表（epoll_ctl：add）    */
    l, _ := net.Listen("tcp",":8080")

    for{
        /*            - 等待 tcp 连接到达                - loop + 非阻塞模式调用 accept                - 若未就绪，则通过 gopark 进行阻塞                - 等待 netpoller 轮询唤醒                     - 检查是否有 io 事件就绪（epoll_wait——nonblock）                     - 若发现事件就绪 通过 goready 唤醒 g                - accept 获取 conn fd 后注册到 epoll 事件表（epoll_ctl：add）                - 返回 conn        */
        conn, _ := l.Accept()
        // goroutine per conn
        go serve(conn)
    }
}

// 处理一笔到来的 tcp 连接
func serve(conn net.Conn){
    /*        - 关闭 conn           - 从 epoll 事件表中移除该 fd（epoll_ctl：remove）           - 销毁该 fd    */
    defer conn.Close()
    var buf []byte
    /*        - 读取连接中的数据           - loop + 非阻塞模式调用 recv (read)           - 若未就绪，则通过 gopark 进行阻塞           - 等待 netpoller 轮询唤醒                - 检查是否有 io 事件就绪（epoll_wait——nonblock）                - 若发现事件就绪 通过 goready 唤醒 g    */
    _, _ = conn.Read(buf)
    /*        - 向连接中写入数据           - loop + 非阻塞模式调用 writev (write)           - 若未就绪，则通过 gopark 进行阻塞           - 等待 netpoller 轮询唤醒                - 检查是否有 io 事件就绪（epoll_wait：nonblock）                - 若发现事件就绪 通过 goready 唤醒 g    */
    _, _ = conn.Write(buf)
}
```  
## 3.2 pollDesc 存储设计  
  
在 golang netpoll 实现中，pollDesc 是一个重要的类型，定义位于 internel/poll/fd_poll_runtime.go 文件中：  
```
type pollDesc struct {
    runtimeCtx uintptr
}
```  
  
不同操作系统对 pollDesc 有着不同的底层实现，此处通过 runtimeCtx 指针指向其底层实现类型实例.  
  
本文基于 linux 系统进行源码走读，有关 pollDesc 具体底层实现代码位于runtime/netpoll.go 文件中，实现类型同样叫做 pollDesc：  
```
// Network poller descriptor.
// No heap pointers.
// 网络 poller 描述符
type pollDesc struct{
    // next 指针，指向其在pollCache 中相邻的下一个 pollDesc 实例
    link *pollDesc 
    // 关联的 fd 句柄
    fd   uintptr

    /*        读事件状态标识器. 里面可能存储的内容包括：            - pdReady：标识读操作已就绪的状态            - pdWait：标识 g 阻塞等待读操作就绪的状态            - g：阻塞等待读操作就绪的  g            - 0：无内容    */
    rg atomic.Uintptr// pdReady, pdWait, G waiting for read or nil
    /*        写事件状态标识器. 里面可能存储的内容包括：            - pdReady：标识写操作已就绪的状态            - pdWait：标识 g 阻塞等待写操作就绪的状态            - g：阻塞等待写操作就绪的  g            - 0：无内容    */
    wg atomic.Uintptr// pdReady, pdWait, G waiting for write or nil
    // ...
}
```  
  
为避免讲解过程中产生歧义，此后我们统一将internel/poll/fd_poll_runtime.go 中的pollDesc 类称为表层pollDesc，runtime/netpoll.go 文件中的 pollDesc 类则维持称呼为pollDesc或里层pollDesc.  
  
在与 epoll 事件表交互前，需要为每个 fd 分配一个 pollDesc 实例，进入事件表时，fd 作为key，pollDesc 则是与之关联的 value.  
  
在 pollDesc 中包含两个核心字段——读/写事件状态标识器 rg/wg，其用于标识 fd 的 io 事件状态以及存储因 io 事件未就绪而 park 的 g 实例. 后续在 io 事件就绪时，能通过 pollDesc 逆向追溯得到g 实例，创造将其唤醒的机会.  
  
![](https://mmbiz.qpic.cn/sz_mmbiz_png/3ic3aBqT2ibZv1CgmoR8HX3RbUKBzMTicDReuMqr98kic0EiaW4UslsbtDzj9PF8MqxuacjplZt3K4SFerzm2bdKlgg/640?wx_fmt=png&from=appmsg "")  
  
在存储结构上，golang 设计了一个名为 pollCache 的缓冲池结构，用于实现 pollDesc实例的复用，内部采用一个单向链表维系 pollDesc 之间的拓扑关系.  
```
// pollDesc 缓冲池，用于实现 pollDesc 对象实例的复用
type pollCache struct {
    // 互斥锁 保证操作的并发安全
    lock  mutex
    // 队首的 pollDesc 实例
    first *pollDesc
}
```  
  
pollCache 中包含两个核心方法，alloc 和 free，分别实现从 cache 中获取 pollDesc 实例以及将用完的 pollDesc 归还给 cache 的操作.  
```
// 从 pollCache 中分配得到一个 pollDesc 实例
func (c *pollCache) alloc()*pollDesc {
    lock(&c.lock)
    // 如果 pollCache 为空，则需要进行初始化
    if c.first ==nil{
         // pdSize = 240
        const pdSize =unsafe.Sizeof(pollDesc{})
        // const pollBlockSize = 4 * 1024
        n := pollBlockSize / pdSize
        // ...

        // Must be in non-GC memory because can be referenced
        // only from epoll/kqueue internals.
        // 分配指定大小的内存空间
        mem := persistentalloc(n*pdSize,0,&memstats.other_sys)
        // 完成指定数量  pollDesc 的初始化
        for i :=uintptr(0); i < n; i++{
            pd :=(*pollDesc)(add(mem, i*pdSize))
            pd.link = c.first
            c.first = pd
        }
    }
    // 取出 pollCache 队首元素
    pd := c.first
    // pollCache 队首指针指向下一个元素
    c.first = pd.link
    lockInit(&pd.lock, lockRankPollDesc)
    unlock(&c.lock)
    return pd
}
```  
```
// 释放一个 pollDesc 实例，将其放回到 pollCache 中
func (c *pollCache) free(pd *pollDesc) {
    lock(&c.lock)
    // 调整指针指向原本 pollCache 中的队首元素
    pd.link = c.first
    // 成为 pollCache 新的队首
    c.first = pd
    unlock(&c.lock)
}
```  
## 3.3 socket 创建流程  
  
下面以net.Listen 方法为入口，沿着创建 socket fd 的流程进行源码走读，该过程中涉及的方法调用栈关系如下：  
  
<table><thead style="line-height: 1.75;background: rgba(0, 0, 0, 0.05);font-weight: bold;color: rgb(63, 63, 63);"><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;">方法</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;">文件</td></tr></thead><tbody><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">net.Listen</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">net/dial.go</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">net.ListenConfig.Listen</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">net/dial.go</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">net.sysListener.listenTCP</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">net/tcpsock_posix.go</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">net.internetSocket</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">net/tcpsock_posix.go</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">net.socket</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">net/sock_posix.go</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">net.netFD.listenStream</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">net/sock_posix.go</td></tr></tbody></table>  

	
![](https://mmbiz.qpic.cn/sz_mmbiz_png/3ic3aBqT2ibZv1CgmoR8HX3RbUKBzMTicDRJTpNC0nGD9Ue9sy38iaMibpGDvaD6hdRYADVEIOroCHpH5rKMu6lr8sg/640?wx_fmt=png&from=appmsg "")  
  
该流程中最核心的方法为位于：net/sock_posix.go 文件的 socket 和 netFD.listenStream 方法，其核心执行步骤包括：  
- • 通过socket 指令创建socket fd；  
  
- • 通过bind 指令将 socket 绑定到指定地址；  
  
- • 通过listen 指令对socket 发起监听；  
  
- • 调用 socket fd 对应表层 pollDesc的 init 方法（会分别执行一次 poll init 和 poll open 流程）  
  
```
// socket returns a network file descriptor that is ready for
// asynchronous I/O using the network poller.
func socket(ctx context.Context, net string, family, sotype, proto int, ipv6only bool, laddr, raddr sockaddr, ctrlFn func(string, string, syscall.RawConn)error)(fd *netFD, err error){
// 通过 syscall socket，以 nonblock 模式创建 socket fd
    s, err := sysSocket(family, sotype, proto)
    fd, err = newFD(s, family, sotype, net)

    // ...
    /*        - 通过 syscall bind 将 socket 绑定到指定地址        - 通过 syscall listen 发起对 socket 监听        - 完成 epoll 事件表创建（全局只执行一次）        - 将 socket fd 注册到 epoll 事件表中，监听读写就绪事件    */
    fd.listenStream(laddr, listenerBacklog(), ctrlFn)}
    // ...
}
```  
```
func (fd *netFD) listenStream(laddr sockaddr, backlog int, ctrlFn func(string, string, syscall.RawConn)error)error{
    // ...
    // 通过 syscall bind 将 socket 绑定到指定地址
    syscall.Bind(fd.pfd.Sysfd, lsa)
    // ...
    // 通过 syscall listen 发起对 socket 监听
    listenFunc(fd.pfd.Sysfd, backlog)
    // ...
    /*        - 完成 epoll 事件表创建（全局只执行一次）        - 将 socket fd 注册到 epoll 事件表中，监听读写就绪事件    */
     fd.init()
    // ...
 }
```  
## 3.4 poll_init 流程  
  
顺着 3.3 小节的流程继续往下，在表层 pollDesc 的init 方法中，会首先确保全局必须调用一次 poll_init 流程，完成 epoll 事件表的初始化，其方法调用栈如下：  
  
<table><thead style="line-height: 1.75;background: rgba(0, 0, 0, 0.05);font-weight: bold;color: rgb(63, 63, 63);"><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;">方法</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;">文件</td></tr></thead><tbody><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">poll.FD.Init</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">internal/poll/fd_unix.go</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">poll.pollDesc.init</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">internal/poll/fd_poll_runtime.go</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">poll.runtime_pollServerInit</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">internal/poll/fd_poll_runtime.go</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime.poll_runtime_pollServerInit</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime/netpoll.go</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime.netpollGenericInit</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime/netpoll.go</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime.netpollinit</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime/netpoll_epoll.go</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime.epollcreate1</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime/netpoll_epoll.go</td></tr></tbody></table>  

	
![](https://mmbiz.qpic.cn/sz_mmbiz_png/3ic3aBqT2ibZv1CgmoR8HX3RbUKBzMTicDR4Tdc5SG9h0Ngj4M53Zu6EbXlicl0EgFBibuG9kBwh2QM7JTE7kP86M2w/640?wx_fmt=png&from=appmsg "")  
  
在表层 pollDesc.init 方法中，会通过 sync.Once 保证执行一次 runtime_pollServerInit 方法，该方法在 linux 系统下的实现为位于 runtime/netpoll.go 中的 runtime.poll_runtime_pollServerInit 方法，最终通过调用 netpollinit 方法，执行epoll_create 指令，完成 epoll 事件表的创建：  
```
// 单例工具
var serverInit sync.Once

func (pd *pollDesc) init(fd *FD) error {
    // 完成 epoll 事件表的创建——全局只执行一次
    serverInit.Do(runtime_pollServerInit)
    // ...
}

func runtime_pollServerInit()
```  
```
//go:linkname poll_runtime_pollServerInit internal/poll.runtime_pollServerInit
func poll_runtime_pollServerInit() {
    // ...
}
```  
```
func netpollinit() {
    // 通过 epoll_create 操作创建 epoll 事件表
    epfd = epollcreate1(_EPOLL_CLOEXEC)
    // ...
    /*        创建 pipe 管道，用于接收信号，如程序终止：            - r：信号接收端，会注册对应的 read 事件到 epoll 事件表中            - w：信号发送端，当有信号到达时，会往 w 中发送信号，并对 r 产生读就绪事件    */
    r, w, errno := nonblockingPipe()
    // 在 epoll 事件表中注册监听 r 的读就绪事件
    ev := epollevent{
        events: _EPOLLIN,
}
    *(**uintptr)(unsafe.Pointer(&ev.data))=&netpollBreakRd
    errno = epollctl(epfd, _EPOLL_CTL_ADD, r,&ev)
    // ...
    // 使用全局变量缓存 pipe 的读写端
    netpollBreakRd =uintptr(r)
    netpollBreakWr =uintptr(w)
}
```  
## 3.5 poll_open 流程  
  
表层pollDesc.init方法中，在确保已完成 poll_init 流程后，就会执行 poll_open 流程，将当前 fd 及 pollDesc 注册到 epoll 事件表中，方法调用栈如下：  
  
<table><thead style="line-height: 1.75;background: rgba(0, 0, 0, 0.05);font-weight: bold;color: rgb(63, 63, 63);"><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;">方法</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;">文件</td></tr></thead><tbody><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">poll.FD.Init</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">internal/poll/fd_unix.go</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">poll.pollDesc.init</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">internal/poll/fd_poll_runtime.go</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">poll.runtime_pollOpen</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">internal/poll/fd_poll_runtime.go</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime.poll_runtime_pollOpen</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime/netpoll.go</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime.netpollopen</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime/netpoll_epoll.go</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime.epollctl</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime/netpoll_epoll.go</td></tr></tbody></table>  

	
![](https://mmbiz.qpic.cn/sz_mmbiz_png/3ic3aBqT2ibZv1CgmoR8HX3RbUKBzMTicDRecWXb7bxGutkZubD2mY8f2QHmdKeHsOv0lyL6ATTcR5J9EdlsSuaww/640?wx_fmt=png&from=appmsg "")  
  
在表层 pollDesc.init 方法中，执行完 poll_open流程后，会获取到里层返回的 pollDesc 实例，将其引用存放在 runtimeCtx 字段中：  
```
func (pd *pollDesc) init(fd *FD)error{
    // ...
    // 将 fd 注册到 epoll 事件表中
    ctx, errno := runtime_pollOpen(uintptr(fd.Sysfd))
    // ...
    // 通过 runtimeCtx 关联与之映射的 netpoll.pollDesc
    pd.runtimeCtx = ctx
}

func runtime_pollOpen(fd uintptr)(uintptr,int)
```  
  
runtime_pollOpen 方法在 linux 系统下的实现为位于 runtime/netpoll.go 中的 runtime.poll_runtime_pollOpen 方法，其中会从 pollCache 中获取一个 pollDesc 实例，并调用 netpollopen方法，执行epoll_ctl（ADD）指令将其添加到 epoll 事件表中：  
```
//go:linkname poll_runtime_pollOpen internal/poll.runtime_pollOpen
func poll_runtime_pollOpen(fd uintptr)(*pollDesc,int){
    // 从 pollcache 中分配出一个 pollDesc 实例
    pd := pollcache.alloc()
    lock(&pd.lock)
    // pollDesc 与 fd 关联
    pd.fd = fd
    // ...
    /*        读就绪事件的状态标识器初始化              - 0：无动作            - 1：读就绪            - 2：阻塞等待读就绪    */
    pd.rg.Store(0)
    // ...
    /*        写就绪事件的状态标识器初始化              - 0：无动作            - 1：写就绪            - 2：阻塞等待写就绪    */
    pd.wg.Store(0)
    // ...
    unlock(&pd.lock)
    // ...
    // 将 fd 添加进入 epoll 事件表中
    errno := netpollopen(fd, pd)
    // ...
    // 返回 pollDesc实例
    return pd,0
}
```  
  
值得一提的是，golang 在执行epoll_ctl（ADD）指令时，会同时将读写就绪事件（EPOLLIN/EPOLLOUT）设为 fd 的监听事件类型，而后续在 netpoll 轮询环节中，则会通过pollDesc 的 rg 和wg 来甄别出 g 关心的具体事件类型究竟是读事件还是写事件.  
```
func netpollopen(fd uintptr, pd *pollDesc) int32{
    /*        通过 epollctl 操作，在 epoll 事件表中注册针对 fd 监听事件          - 操作类型宏指令：_EPOLL_CTL_ADD —— 添加 fd 并注册监听事件          - 事件类型：epollevent.events                - _EPOLLIN：监听读就绪事件                - _EPOLLOUT：监听写就绪事件                - _EPOLLRDHUP：监听中断事件                - _EPOLLET：采用 edge trigger 边缘触发模式进行监听          - 回调数据：epollevent.data —— pollDesc 实例指针    */
    var ev epollevent
    ev.events = _EPOLLIN | _EPOLLOUT | _EPOLLRDHUP | _EPOLLET
    *(**pollDesc)(unsafe.Pointer(&ev.data))= pd
    return-epollctl(epfd, _EPOLL_CTL_ADD,int32(fd),&ev)
}
```  
  
接下来梳理一下，有哪些流程中会触发到poll open流程呢？  
  
首先是 net.Listen 流程，在 socket fd 创建完成后，需要通过poll open流程将其注册到 epoll事件表中，完整的调用链路如下：  
  
<table><thead style="line-height: 1.75;background: rgba(0, 0, 0, 0.05);font-weight: bold;color: rgb(63, 63, 63);"><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;">方法</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;">文件</td></tr></thead><tbody><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">net.Listen</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">net/dial.go</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">net.ListenConfig.Listen</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">net/dial.go</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">net.sysListener.listenTCP</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">net/tcpsock_posix.go</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">net.internetSocket</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">net/tcpsock_posix.go</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">net.socket</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">net/sock_posix.go</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">net.netFD.listenStream</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">net/sock_posix.go</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">poll.FD.Init</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">internal/poll/fd_unix.go</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">poll.pollDesc.init</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">internal/poll/fd_poll_runtime.go</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">poll.runtime_pollOpen</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">internal/poll/fd_poll_runtime.go</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime.poll_runtime_pollOpen</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime/netpoll.go</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime.netpollopen</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime/netpoll_epoll.go</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime.epollctl</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime/netpoll_epoll.go</td></tr></tbody></table>  

	
接下来是在 net.Listener.Accept 流程中，当 accept 得到新连接后，会将连接封装成表层pollDesc 实例，并执行poll open流程将其注册到epoll事件表中：  
  
<table><thead style="line-height: 1.75;background: rgba(0, 0, 0, 0.05);font-weight: bold;color: rgb(63, 63, 63);"><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;">方法</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;">文件</td></tr></thead><tbody><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">net.TCPListener.Accept</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">net/tcpsock.go</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">net.TCPListener.accept</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">net/tcpsock_posix.go</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">net.netFD.accept</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">net/fd_unix.go</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">net.netFD.init</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">net/fd_unix.go</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">poll.FD.Init</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">internal/poll/fd_unix.go</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">poll.pollDesc.init</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">internal/poll/fd_poll_runtime.go</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">poll.runtime_pollOpen</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">internal/poll/fd_poll_runtime.go</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime.poll_runtime_pollOpen</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime/netpoll.go</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime.netpollopen</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime/netpoll_epoll.go</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime.epollctl</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime/netpoll_epoll.go</td></tr></tbody></table>  

```
func (fd *netFD) accept()(netfd *netFD, err error){
    // 通过 syscall accept 接收到来的 conn fd
    d, rsa, errcall, err := fd.pfd.Accept()
    // ...
    // 封装到来的 conn fd
    netfd, err = newFD(d, fd.family, fd.sotype, fd.net)
    // 将 conn fd 注册到 epoll 事件表中
    err = netfd.init()
    // ...
    return netfd,nil
}
```  
## 3.6 poll_close 流程  
  
当一笔 conn 要被关闭时，会执行 poll close 流程，此时会通过表层 pollDesc的 runtimeCtx 字段获取到里层 pollDesc 的引用，并通过 epoll_ctl（DEL）指令实现从epoll 事件表中移除指定 fd 及 pollDesc 的效果. 其核心方法调用栈如下：  
  
<table><thead style="line-height: 1.75;background: rgba(0, 0, 0, 0.05);font-weight: bold;color: rgb(63, 63, 63);"><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;">方法</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;">文件</td></tr></thead><tbody><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">net.conn.Close</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">net/net.go</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">net.netFD.Close</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">net/fd_posix.go</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">poll.FD.Close</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">internal/poll/fd_unix.go</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">poll.FD.decref</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">internal/poll/fd_mutex.go</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">poll.FD.destroy</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">internal/poll/fd_unix.go</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">poll.pollDesc.close</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">internal/poll/fd_poll_runtime.go</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">poll.runtime_pollClose</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">internal/poll/fd_poll_runtime.go</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime.poll_runtime_pollClose</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime/netpoll.go</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime.netpollclose</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime/netpoll_epoll.go</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime.epollctl</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime/netpoll_epoll.go</td></tr></tbody></table>  

	
![](https://mmbiz.qpic.cn/sz_mmbiz_png/3ic3aBqT2ibZv1CgmoR8HX3RbUKBzMTicDRukIFEWrEVZcIgsO87BwH5pDVC1Ae3zkQdQ6iaibIv2uXDzJtgQZyxp0w/640?wx_fmt=png&from=appmsg "")  
  
runtime_pollClose 方法在 linux 系统下的实现为位于 runtime/netpoll.go 中的 runtime.poll_runtime_pollClose 方法，其中会调用 epoll_ctl（DEL）指令将 fd 从 epoll 事件表中删除并将 pollDesc 实例归还到 pollCache中.  
```
func (pd *pollDesc) close() {
    // 通过 runtimeCtx 映射到netpoll.pollDesc
    runtime_pollClose(pd.runtimeCtx)
    pd.runtimeCtx = 0
}

func runtime_pollClose(ctx uintptr)
```  
```
//go:linkname poll_runtime_pollClose internal/poll.runtime_pollClose
func poll_runtime_pollClose(pd *pollDesc) {
    // 通过 epoll_ctl_del 操作，从 epoll 事件表中移除指定 fd
    netpollclose(pd.fd)
    // 从 pollCache 中移除对应的 pollDesc 实例
    pollcache.free(pd)
}
```  
```
func netpollclose(fd uintptr) int32 {
    var ev epollevent
    return -epollctl(epfd, _EPOLL_CTL_DEL, int32(fd), &ev)
}
```  
## 3.7 poll_wait 流程  
  
接下来是 poll_wait 操作，其最终会通过 gopark 操作来使得当前 g 陷入到用户态阻塞，源码方法调用栈如下：  
  
<table><thead style="line-height: 1.75;background: rgba(0, 0, 0, 0.05);font-weight: bold;color: rgb(63, 63, 63);"><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;">方法</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;">文件</td></tr></thead><tbody><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">poll.pollDesc.wait</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">internal/poll/fd_poll_runtime.go</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">poll.runtime_pollWait</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">internal/poll/fd_poll_runtime.go</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime.poll_runtime_pollWait</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime/netpoll.go</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime.netpollblock</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime/netpoll.go</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime.gopark</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime.proc.go</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime.netpollblockcommit</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime/netpoll.go</td></tr></tbody></table>  

	
![](https://mmbiz.qpic.cn/sz_mmbiz_png/3ic3aBqT2ibZv1CgmoR8HX3RbUKBzMTicDRSzHgv1XdSKTvMvcnlNtKicsvhtPicpKVfUR1CpYog0jdnqQrBMfwr0qg/640?wx_fmt=png&from=appmsg "")  
  
在表层 pollDesc.wait 方法中，会通过runtimeCtx获取到里层 pollDesc 引用，进而调用linux 系统下位于 runtime/netpoll.go 文件的 poll_runtime_pollWait 方法，执行 epoll_ctl（DEL）指令.  
```
/*    - 标识出当前 g 关心的 io 事件         - mode：r——等待读就绪事件 w——等待写就绪事件    - gopark 当前g 陷入用户态阻塞*/
func (pd *pollDesc) wait(mode int, isFile bool)error{
    // 确保已经关联映射到某个 netpoll.pollDesc
    if pd.runtimeCtx ==0{
        return errors.New("waiting for unsupported file type")
    }
    res := runtime_pollWait(pd.runtimeCtx, mode)
    // ...
}

func runtime_pollWait(ctx uintptr, mode int) int
```  
```
// poll_runtime_pollWait, which is internal/poll.runtime_pollWait,
// waits for a descriptor to be ready for reading or writing,
// according to mode, which is 'r' or 'w'.

//go:linkname poll_runtime_pollWait internal/poll.runtime_pollWait
func poll_runtime_pollWait(pd *pollDesc, mode int)int{
    // ...
    for !netpollblock(pd,int32(mode),false){
        // ...  
    }
    // ...
}
```  
  
在该流程最底层的 netpollblock 方法中，针对于依赖 io 事件未就绪的 g，会通过 gopark 操作令其陷入用户态阻塞中，在 gopark 方法中会闭包调用 netpollblockcommit 方法，其中会根据 g 关心的事件类型将 g 实例存储在 pollDesc 的 rg 或 wg 容器中.  
> 需要注意，针对于同一个 fd 的同种事件类型，同一时刻有且只能有一个 g 被挂载在事件状态标识器中，参见方法注释  
  
```
// returns true if IO is ready, or false if timedout or closed
// waitio - wait only for completed IO, ignore errors
// can hold only a single waiting goroutine for each mode.
/*    针对某个 pollDesc 实例，监听指定的mode 就绪事件        - 返回true——已就绪  返回false——因超时或者关闭导致中断        - 其他情况下，会通过 gopark 操作将当前g 阻塞在该方法中*/
func netpollblock(pd *pollDesc, mode int32, waitio bool)bool{
// 根据mode判断关心的是读就绪事件r 还是写就绪事件w，取得对应的状态标识器
    gpp :=&pd.rg
    if mode =='w'{
        gpp =&pd.wg
    }

    // loop 自旋模型
    for{
    // const pdRead = 1 
        /*             关心的 io事件已就绪，则 cas更新状态标识器，并直接返回        */
        if gpp.CompareAndSwap(pdReady,0){
            returntrue
        }
        // const pdWait = 2
        /*             关心的 io事件未就绪，则 cas更新状态标识器为阻塞等待状态，并打破循环                */
        if gpp.CompareAndSwap(0, pdWait){
            break
        }
        // ...
    }

    // ...
    // gopark 进入阻塞态
    gopark(netpollblockcommit,unsafe.Pointer(gpp), waitReasonIOWait, traceEvGoBlockNet,5)

    // 当前g 从阻塞态被唤醒，把pollDesc 状态标识器置为 0，并判断是否因为所关心io 事件就绪而被唤醒
    old := gpp.Swap(0)
    // ...
    return old == pdReady
}
```  
```
// 将 gpp 状态标识器的值由 pdWait 修改为当前 g 
func netpollblockcommit(gp *g, gpp unsafe.Pointer) bool {
    r := atomic.Casuintptr((*uintptr)(gpp), pdWait, uintptr(unsafe.Pointer(gp)))
    if r {.
        atomic.Xadd(&netpollWaiters, 1)
    }
    return r
}
```  
  
接下来观察会触发 poll_wait 的流程.  
  
首先是在 listener.Accept 流程中，如果 socket fd 下尚无连接到达，则会执行 poll wait 将当前 g 阻塞并挂载到 socket fd 对应 pollDesc 的 rg 中：  
  
<table><thead style="line-height: 1.75;background: rgba(0, 0, 0, 0.05);font-weight: bold;color: rgb(63, 63, 63);"><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;">方法</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;">文件</td></tr></thead><tbody><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">net.TCPListener.Accept</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">net/tcpsock.go</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">net.TCPListener.accept</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">net/tcpsock_posix.go</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">net.netFD.accept</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">net/fd_unix.go</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">poll.FD.Accept</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">internal/poll/fd_unix.go</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">poll.pollDesc.waitRead</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">internal/poll/fd_poll_runtime.go</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">poll.pollDesc.waitRead</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">internal/poll/fd_poll_runtime.go</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">poll.pollDesc.wait</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">internal/poll/fd_poll_runtime.go</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">poll.runtime_pollWait</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">internal/poll/fd_poll_runtime.go</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime.poll_runtime_pollWait</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime/netpoll.go</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime.netpollblock</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime/netpoll.go</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime.gopark</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime.proc.go</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime.netpollblockcommit</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime/netpoll.go</td></tr></tbody></table>  

```
// Accept wraps the accept network call.
func (fd *FD)Accept()(int, syscall.Sockaddr,string,error){
    // ...
    for{
        // 以nonblock 模式发起一次 syscall accept 尝试接收到来的 conn
        s, rsa, errcall, err := accept(fd.Sysfd)
        // 接收conn成功，直接返回结果
        if err ==nil{
            return s, rsa,"", err
        }
        switch err {
            // 中断类错误直接忽略
            case syscall.EINTR:
                    continue
            // 当前未有到达的conn 
            case syscall.EAGAIN:
            // 走入 poll_wait 流程，并标识关心的是 socket fd 的读就绪事件
            // (当conn 到达时，表现为 socket fd 可读)
                if fd.pd.pollable(){
                // 倘若读操作未就绪，当前g 会 park 阻塞在该方法内部，直到因超时或者事件就绪而被 netpoll ready 唤醒
                    if err = fd.pd.waitRead(fd.isFile); err ==nil{
                        continue
                    }
                }
                // ...
        }
        // ...
    }
}
```  
```
// 指定 mode 为 r 标识等待的是读就绪事件，然后走入更底层的 poll_wait 流程
func (pd *pollDesc) waitRead(isFile bool) error {
    return pd.wait('r', isFile)
}
```  
  
其次是在 conn.Read 流程中，如果 conn fd 下读操作尚未就绪（尚无数据到达），则会执行 poll wait 将当前 g 阻塞并挂载到 conn fd 对应 pollDesc 的 rg 中：  
  
<table><thead style="line-height: 1.75;background: rgba(0, 0, 0, 0.05);font-weight: bold;color: rgb(63, 63, 63);"><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;">方法</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;">文件</td></tr></thead><tbody><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">net.conn.Read</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">net/net.go</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">net.netFD.Read</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">net/fd_posix.go</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">poll.FD.Read</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">internal/poll/fd_unix.go</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">poll.pollDesc.waitRead</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">internal/poll/fd_poll_runtime.go</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">poll.pollDesc.wait</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">internal/poll/fd_poll_runtime.go</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">poll.runtime_pollWait</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">internal/poll/fd_poll_runtime.go</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime.poll_runtime_pollWait</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime/netpoll.go</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime.netpollblock</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime/netpoll.go</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime.gopark</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime.proc.go</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime.netpollblockcommit</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime/netpoll.go</td></tr></tbody></table>  

```
// Read implements io.Reader.
func (fd *FD)Read(p []byte)(int,error){
    // ... 
    for{
        // 以非阻塞模式执行一次syscall read 操作 
        n, err := ignoringEINTRIO(syscall.Read, fd.Sysfd, p)
        if err !=nil{
            n =0
            // 走入 poll_wait 流程，并标识关心的是该 fd 的读就绪事件
            if err == syscall.EAGAIN && fd.pd.pollable(){
            // 倘若读操作未就绪，当前g 会 park 阻塞在该方法内部，直到因超时或者事件就绪而被 netpoll ready 唤醒
                if err = fd.pd.waitRead(fd.isFile); err ==nil{
                    continue
                }
            }
        }
        err = fd.eofError(n, err)
        return n, err
    }
}
```  
  
最后是 conn.Write 流程，如果 conn fd 下写操作尚未就绪（缓冲区空间不足），则会执行 poll wait 将当前 g 阻塞并挂载到 conn fd 对应 pollDesc 的wg中：  
  
<table><thead style="line-height: 1.75;background: rgba(0, 0, 0, 0.05);font-weight: bold;color: rgb(63, 63, 63);"><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;">方法</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;">文件</td></tr></thead><tbody><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">net.conn.Write</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">net/net.go</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">net.netFD.Write</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">net/fd_posix.go</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">poll.FD.Write</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">internal/poll/fd_unix.go</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">poll.pollDesc.waitWrite</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">internal/poll/fd_poll_runtime.go</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">poll.pollDesc.wait</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">internal/poll/fd_poll_runtime.go</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">poll.runtime_pollWait</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">internal/poll/fd_poll_runtime.go</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime.poll_runtime_pollWait</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime/netpoll.go</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime.netpollblock</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime/netpoll.go</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime.gopark</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime.proc.go</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime.netpollblockcommit</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime/netpoll.go</td></tr></tbody></table>  

```
// Write implements io.Writer.
func (fd *FD)Write(p []byte)(int,error){
    // ... 
    for{
    // ...
    // 以非阻塞模式执行一次syscall write操作
        n, err := ignoringEINTRIO(syscall.Write, fd.Sysfd, p[nn:max])
        if n >0{
            nn += n
        }
        // 缓冲区内容都已写完，直接退出
        if nn ==len(p){
            return nn, err
        }

    // 走入 poll_wait 流程，并标识关心的是该 fd 的写就绪事件
    if err == syscall.EAGAIN && fd.pd.pollable(){
        // 倘若写操作未就绪，当前g 会 park 阻塞在该方法内部，直到因超时或者事件就绪而被 netpoll ready 唤醒
        if err = fd.pd.waitWrite(fd.isFile); err ==nil{
            continue
        }
    }
    // ...  
    
}
```  
```
// 指定 mode 为 r 标识等待的是读就绪事件，然后走入更底层的 poll_wait 流程
func (pd *pollDesc) waitWrite(isFile bool) error {
    return pd.wait('w', isFile)
}
```  
## 3.8 net_poll 流程  
  
最后压轴登场的是尤其关键的 net poll 流程.  
  
3.7 小节中交待了，当 g 发现关心的 io 事件未就绪时，会通过 gopark 操作将自身陷入阻塞，并且将 g 挂载在 pollDesc 的 rg/wg 中.  
  
而本小节介绍的 net_poll 流程就负责轮询获取已就绪 pollDesc 对应的 g，将其返回给上游的 gmp 调度系统，对其进行唤醒和调度.  
  
在常规的 net poll 流程中，会采用非阻塞模式执行 epoll_wait 操作，但唯独在 p 大面积空闲时，全局会有一个 p 负责留守 net_poll，此时其会以阻塞或超时模式执行 net_poll 流程并以同样的模式调用epoll_wait 指令.  
  
net_poll 流程的调用栈如下，其本身只用于返回达到就绪条件的 g list，具体的唤醒和调度操作是由上游执行的：  
  
<table><thead style="line-height: 1.75;background: rgba(0, 0, 0, 0.05);font-weight: bold;color: rgb(63, 63, 63);"><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;">方法</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;">文件</td></tr></thead><tbody><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime.netpoll</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime/netpoll_epoll.go</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime.netpollready</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime/netpoll.go</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime.netpollunblock</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime/netpoll.go</td></tr></tbody></table>  

	
![](https://mmbiz.qpic.cn/sz_mmbiz_png/3ic3aBqT2ibZv1CgmoR8HX3RbUKBzMTicDRy7p3zMl5OCGibzfpsZEcpHEUu8BIPnoCOyjTh7cGE9jdLfXDec7YrNA/640?wx_fmt=png&from=appmsg "")  
  
net_poll 流程入口位于 runtime/netpoll_epoll.go 文件中，其中有几个关键点我们作个概述，其他内容大家参考源码以及其中给出的注释：  
- • 根据入参中的 delay，决定调用 epoll_wait 指令的模式是非阻塞、阻塞还是超时. 通常情况下 delay 值为 0，对应为非阻塞模式  
  
- • 执行 epoll_wait 操作，获取就绪的 io 事件 list. 一轮最多获取 128 个  
  
- • 根据就绪事件类型，将 mode 分为 w（写就绪事件）和 r（读就绪事件）  
  
- • 获取 event 中存储的 pollDesc 实例  
  
- • 根据 mode，获取 pollDesc 实例中 rg或者wg中的 g 实例，加入 glist  
  
- • 将 glist 返回给上游调用方，进行唤醒操作  
  
```
// netpoll checks for ready network connections.
// Returns list of goroutines that become runnable.
/*    - netpoll 流程用于轮询检查是否有就绪的 io 事件    - 如果有就绪 io 事件，还需要检查是否有 pollDesc 中的 g 关心该事件    - 找到所有关心该就绪 io 事件的 g，添加到 list 中返回给上游进行 goready 唤醒*/
func netpoll(delay int64) gList {
    /*        根据传入的 delay 参数，决定调用 epoll_wait 的模式            - delay < 0：设为 -1 阻塞模式（在 gmp 调度流程中，如果某个 p 迟迟获取不到可执行的 g 时，会通过该模式，使得 thread 陷入阻塞态，但该情况全局最多仅有一例）            - delay = 0：设为 0 非阻塞模式（通常情况下为此模式，包括 gmp 常规调度流程、gc 以及全局监控线程 sysmon 都是以此模式触发的 netpoll 流程）            - delay > 0：设为超时模式（在 gmp 调度流程中，如果某个 p 迟迟获取不到可执行的 g 时，并且通过 timer 启动了定时任务时，会令 thread 以超时模式执行 epoll_wait 操作）    */
    var waitms int32
    if delay <0{
        waitms =-1
    }elseif delay ==0{
        waitms =0
    // 针对 delay 时长取整
    }elseif delay <1e6{
        waitms =1
    }elseif delay <1e15{
        waitms =int32(delay /1e6)
    }else{
    // 1e9 ms == ~11.5 days.
        waitms =1e9
    }
    // 一次最多接收 128 个 io 就绪事件 
    var events [128]epollevent
retry:
    // 以指定模式，调用 epoll_wait 指令
    n := epollwait(epfd,&events[0],int32(len(events)), waitms)
    // ...

    // 遍历就绪的每个 io 事件 
    var toRun gList
    for i :=int32(0); i < n; i++{
        ev :=&events[i]
        if ev.events ==0{
            continue
        }

        // pipe 接收端的信号量处理
        if*(**uintptr)(unsafe.Pointer(&ev.data))==&netpollBreakRd {
            // ...
        }

        /*             根据 io 事件类型，标识出 mode：                 - EPOLL_IN -> r；                 - EPOLL_OUT -> w;                 - 错误或者中断事件 -> r & w;        */
        var mode int32
        if ev.events&(_EPOLLIN|_EPOLLRDHUP|_EPOLLHUP|_EPOLLERR)!=0{
            mode +='r'
        }
        if ev.events&(_EPOLLOUT|_EPOLLHUP|_EPOLLERR)!=0{
            mode +='w'
        }
        // 根据 epollevent.data 获取到监听了该事件的 pollDesc 实例
        if mode !=0{
            pd :=*(**pollDesc)(unsafe.Pointer(&ev.data))
        // ...   
        // 尝试针对对应 pollDesc 进行唤醒操作
            netpollready(&toRun, pd, mode)
        }
    }
    return toRun
}
```  
```
/*    epollwait 操作：        - epfd：epoll 事件表 fd 句柄        - ev：用于承载就绪 epoll event 的容器        - nev：ev 的容量        - timeout：            - -1：阻塞模式            - 0：非阻塞模式：            - >0：超时模式. 单位 ms        - 返回值 int32：就绪的 event 数量*/
func epollwait(epfd int32, ev *epollevent, nev, timeout int32) int32
```  
```
// It declares that the fd associated with pd is ready for I/O.
// The toRun argument is used to build a list of goroutines to return
// from netpoll. The mode argument is 'r', 'w', or 'r'+'w' to indicate
/*    根据 pd 以及 mode 标识的 io 就绪事件，获取需要进行 ready 唤醒的 g list    对应 g 会存储到 toRun 这个 list 容器当中*/
func netpollready(toRun *gList, pd *pollDesc, mode int32){
    var rg, wg *g
    if mode =='r'|| mode =='r'+'w'{
    // 倘若到达事件包含读就绪，尝试获取需要 ready 唤醒的 g
        rg = netpollunblock(pd,'r',true)
    }
    if mode =='w'|| mode =='r'+'w'{
    // 倘若到达事件包含写就绪，尝试获取需要 ready 唤醒的 g
        wg = netpollunblock(pd,'w',true)
    }
    // 找到需要唤醒的 g，添加到 glist 中返回给上层
    if rg !=nil{
        toRun.push(rg)
    }
    if wg !=nil{
        toRun.push(wg)
    }
}
```  
```
/*    根据指定的就绪io 事件类型以及 pollDesc，判断是否有 g 需要被唤醒. 若返回结果非空，则为需要唤醒的 g*/
func netpollunblock(pd *pollDesc, mode int32, ioready bool)*g {
// 根据 io 事件类型，获取 pollDesc 中对应的状态标识器
    gpp :=&pd.rg
    if mode =='w'{
        gpp =&pd.wg
    }

    for{
        // 从 gpp 中取出值，此时该值应该为调用过 park 操作的 g
        old := gpp.Load()
        // ...  
        if ioready {
            new= pdReady
        }
        // 通过 cas 操作，将 gpp 值由 g 置换成 pdReady
        if gpp.CompareAndSwap(old,new){
            // 返回需要唤醒的 g   
            return(*g)(unsafe.Pointer(old))
        }
    }
}
```  
  
那么，net_poll 流程究竟会在哪个环节中被触发呢？我们同样通过源码加以佐证.  
  
![](https://mmbiz.qpic.cn/sz_mmbiz_png/3ic3aBqT2ibZv1CgmoR8HX3RbUKBzMTicDRwRg0E3JgQsNibwM2UGkRwH6rCjXMQUS1o3iaEmd3QTaEdqiboIpLXWgHQ/640?wx_fmt=png&from=appmsg "")  
  
**1）gmp 调度流程**  
  
这是属于最常规的 net poll 触发流程，方法调用栈如下：  
  
<table><thead style="line-height: 1.75;background: rgba(0, 0, 0, 0.05);font-weight: bold;color: rgb(63, 63, 63);"><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;">方法</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;">文件</td></tr></thead><tbody><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime.schedule</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime/proc.go</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime.findrunnable</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime/proc.go</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime.netpoll</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime/netpoll_epoll.go</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime.netpollready</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime/netpoll.go</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime.netpollunblock</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime/netpoll.go</td></tr></tbody></table>  

	
runtime.findrunnable 方法用于给 p 寻找合适的 g 进行调度. 检索优先级可以参照下方给出的代码注释，这里单独强调两个点：  
- • 在常规流程中，当 p 发现本地队列 localq 和全局队列 globalq 都没有 g 时，就会以非阻塞模式触发一次 netpoll 流程，获取 io 事件就绪的 glist，取出首个 g 进行调度，其余 g 会置为就绪态并添加到全局队列 globalq 中  
  
- • 特殊情况下，倘若 p 没找到合适的 g 且没有 gc 任务需要协助时，会在将自身置为 idle 态之前，保证全局有一个 p 进行 net_poll 留守，以阻塞或者超时模式执行 epoll_wait 操作，避免有 io 事件到达时出现响应不及时的情况  

```
// gmp 核心调度流程：g0 为当前 p 找到下一个调度的  g
    /*        pick g 的核心逻辑：             1）每调度 61 次，需要专门尝试处理一次全局队列（防止饥饿）             2）尝试从本地队列中获取 g             3）尝试从全局队列中获取 g             4）以【非阻塞模式】调度 netpoll 流程，获取所有需要唤醒的 g 进行唤醒，并获取其中的首个g             5）从其他 p 中窃取一半的 g 填充到本地队列             6）仍找不到合适的 g，则协助 gc              7）以【阻塞或者超时】模式，调度netpoll 流程（全局仅有一个 p 能走入此分支）             8）当前m 添加到全局队列的空闲队列中，停止当前 m    */

func findRunnable()(gp *g, inheritTime, tryWakeP bool){
    // ..
    /*        同时满足下述三个条件，发起一次【非阻塞模式】的 netpoll 流程：            - epoll事件表初始化过            - 有 g 在等待io 就绪事件            - 没有空闲 p 在以【阻塞或超时】模式发起 netpoll 流程    */
    if netpollinited()&& atomic.Load(&netpollWaiters)>0&& atomic.Load64(&sched.lastpoll)!=0{
        // 以非阻塞模式发起一轮 netpoll，如果有 g 需要唤醒，一一唤醒之，并返回首个 g 给上层进行调度
        if list := netpoll(0);!list.empty(){// non-blocking
            // 获取就绪 g 队列中的首个 g
            gp := list.pop()
            // 将就绪 g 队列中其余 g 一一置为就绪态，并添加到全局队列
            injectglist(&list)
            // 把首个g 也置为就绪态
            casgstatus(gp,_Gwaiting,_Grunnable)
            // ...   
            //返回 g 给当前 p进行调度
            return gp,false,false
        }
    }

    // ...
    /*        同时满足下述三个条件，发起一次【阻塞或超时模式】的 netpoll 流程：            - epoll事件表初始化过            - 有 g 在等待io 就绪事件            - 没有空闲 p 在以【阻塞或超时】模式发起 netpoll 流程    */
    if netpollinited()&&(atomic.Load(&netpollWaiters)>0|| pollUntil !=0)&& atomic.Xchg64(&sched.lastpoll,0)!=0{
    // 默认为阻塞模式  
        delay :=int64(-1)
        // 存在定时时间，则设为超时模式
        if pollUntil !=0{
            delay = pollUntil - now
        // ...   
        }
        // 以【阻塞或超时模式】发起一轮 netpoll
        list := netpoll(delay)// block until new work is available 
    }
    // ...    
}
```  
  
**2）gc 并发标记流程：**  
  
为了避免因 gc 而导致 io 事件的处理产生延时或者阻塞，当有 p 以空闲模式 idleMode（当前 p 因找不到合适的 g 进行调度，而选择主动参与 gc 协作） 执行 gc 并发标记流程时，会间隔性地以非阻塞模式触发 net_poll 流程：  
  
<table><thead style="line-height: 1.75;background: rgba(0, 0, 0, 0.05);font-weight: bold;color: rgb(63, 63, 63);"><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;">方法</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;">文件</td></tr></thead><tbody><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime.gcDrain</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime/mgcmark.go</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime.pollWork</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime/proc.go</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime.netpoll</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime/netpoll_epoll.go</td></tr></tbody></table>  

```
// gc 
func gcDrain(gcw *gcWork, flags gcDrainFlags){
    // ...
    // 判断是否以 idle 模式执行 gc 标记流程 
    idle := flags&gcDrainIdle !=0

    // ... 
    var check func()bool
    // ...
    if idle {
        check = pollWork
    }

    for(...some condition){
        // do something...
        // do check function
        if check !=nil&& check(){
            break
        }
        // ...
    }
    // ...
}
```  
```
func pollWork() bool{
    // ...
    // 若全局队列或 p 的本地队列非空，则提前返回
    /*        同时满足下述三个条件，发起一次【非阻塞模式】的 netpoll 流程：            - epoll事件表初始化过            - 有 g 在等待io 就绪事件            - 没有空闲 p 在以【阻塞或超时】模式发起 netpoll 流程    */
    if netpollinited()&& atomic.Load(&netpollWaiters)>0&& sched.lastpoll !=0{
    // 所有取得 g 更新为就绪态并添加到全局队列
        if list := netpoll(0);!list.empty(){
            injectglist(&list)
            return true
        }
    }
    // ...
}
```  
  
此外，当程序在经历过一次 STW（stop the world）后，随后到来的 start the world 流程中也会执行 net_poll 操作，同样也是采用非阻塞模式：  
  
<table><thead style="line-height: 1.75;background: rgba(0, 0, 0, 0.05);font-weight: bold;color: rgb(63, 63, 63);"><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;">方法</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;">文件</td></tr></thead><tbody><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime.startTheWorldWithSema</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime/proc.go</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime.netpoll</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime/netpoll_epoll.go</td></tr></tbody></table>  

```
func startTheWorldWithSema(emitTraceEvent bool) int64{
    // 断言世界已停止
    assertWorldStopped()
    // ...
    // 如果 epoll 事件表初始化过，则以非阻塞模式执行一次 netpoll
    if netpollinited(){
    // 所有取得的 g 置为就绪态并添加到全局队列
        list := netpoll(0)// non-blocking
        injectglist(&list)
    }
    // ...
}
```  
  
**3）sysmon 流程：**  
  
在 golang 程序启动时，有一个全局唯一的 sysmon thread 负责执行监控任务，比如因 g 执行过久或者 m syscall 时间过长而发起的抢占调度流程都是由这个 sysmon 负责的. 在其中也会每隔 10 ms 发起一次非阻塞的 net_poll 流程：  
  
<table><thead style="line-height: 1.75;background: rgba(0, 0, 0, 0.05);font-weight: bold;color: rgb(63, 63, 63);"><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;">方法</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;">文件</td></tr></thead><tbody><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime.main</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime/proc.go</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime.sysmon</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime/proc.go</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime.netpoll</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime/netpoll_epoll.go</td></tr></tbody></table>  

```
// The main goroutine.
func main(){
// ...
// 新建一个 m，直接运行 sysmon 函数
    systemstack(func(){
        newm(sysmon,nil,-1)
    })

    // ...
}

// 全局唯一监控线程的执行函数
func sysmon(){
// ...
for{
// ...
/*        同时满足下述三个条件，发起一次【非阻塞模式】的 netpoll 流程：            - epoll事件表初始化过            - 没有空闲 p 在以【阻塞或超时】模式发起 netpoll 流程            - 距离上一次发起 netpoll 流程的时间间隔已超过 10 ms    */
        lastpoll :=int64(atomic.Load64(&sched.lastpoll))
        if netpollinited()&& lastpoll !=0&& lastpoll+10*1000*1000< now {
            // 以非阻塞模式发起 netpoll
            list := netpoll(0)// non-blocking - returns list of goroutines
            // 获取到的  g 置为就绪态并添加到全局队列中
            if!list.empty(){
                // ...
                injectglist(&list)
                // ...
            }
        }
    // ...  
    }
}
```  
# 4 总结  
  
祝贺各位，至此我们已完成本系列的首篇内容的学习，在本篇中，我们介绍的知识点包括：  
- • io 多路复用技术思路推演  
  
- • epoll 技术底层原理  
  
- • golang netpoll 机制与 epoll 的关联以及在此基础上的适配改造  
  
- • golang netpoll 机制的底层源码走读  
  
同时，我们也对未来即将到来的两篇内容作个展望：  
- • 第二篇：C++ 从零实现 epoll server  
  
- • 第三篇：C++ 从零实现 http server  
  
