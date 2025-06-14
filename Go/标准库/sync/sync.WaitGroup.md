#toread
#  Go并发编程之sync.WaitGroup  
原创 小徐先生1212  小徐先生的编程世界   2023-05-26 19:03  
  
# 0 前言  
  
今天想和大家讨论的主题是 Golang 中的并发等待组工具 sync.WaitGroup. 知识点与知识点之间是可以延展关联的，在步入今天的正题之间，先做个前期提要，回顾下几个月时间下来和大家探讨过的有关 Golang 并发编程的话题，梳理下彼此之间的关联性：  
- • Golang 是门天然支持高并发的语言，其中 goroutine 是经由 Go 优化改良过的协程，是运作于经典的 GMP 体系之下的最小调度单元. （如果想展开这个话题，可以阅读我之前发表的文章——Golang GMP 原理）  
  
- • 在聊 Golang GMP 时，我和大家讨论了 goroutine 的调度方式分为主动让渡和被动调度. 其中触发被动调度的常见方式包括通道 channel 和单机锁 sync.Mutex. 在此之上，今天再补充另一种可能触发 goroutine 被动调度的工具——并发等待组 sync.WaitGroup  
  
- • 在并发编程中，如何使得异步运行的 goroutine 之间建立一种默契的协作关系，这是一个非常关键的话题. channel 是达成这个目标的一种实现方式，不同 goroutine 之间可以通过并发通道 channel 完成信息的传递，从而促成协作关系. （如果想展开这个话题，可以阅读我之前发表的文章——Golang Channel 实现原理）  
  
- • 当 goroutine 之间需要建立明确的层级关系. 倘若父 goroutine 希望持有子 goroutine 的生杀大权，并且保证父 goroutine 消亡时能连带回收其创建的所有子 goroutine ，此时可以使用到 Golang 上下文工具 context，完成父 goroutine 对 子 goroutine 的生命周期控制（如果想展开这个话题，可以阅读我之前发表的文章——Golang context 实现原理）  
  
具备了以上基础知识后，今天我们百尺竿头更进一步，探讨一种新的 goroutine 协作机制——等待聚合模式.  
  
在这种模式下，父 goroutine 在创建一系列子 goroutine 后，可以选择在一个合适的时机对所有子 goroutine 的执行结果进行等待聚合，直到所有子 goroutine 都执行完成之后，父 goroutine 才会继续往前推进. 要达成这种协作模式最合适的工具，就是我们今天要聊的主角——Golang 中的并发等待组工具 sync.WaitGroup.  
  
   
# 1 场景问题探讨  
## 1.1 场景题目  
  
首先以一个场景问题作为切入点：  
  
有一个主管（leader）在负责一个规模庞大的项目. 作为 leader 的角色，他需要充分发挥自己的统筹能力，合理地对项目进行模块拆解和职责划分，让手下的一众同学（follower）能够团结协作、各司其职，当所有 follower 完成工作后，再在 leader 这一层对项目的进行整体把控，作为一个完整的产品进行交付.  
  
于是，leader 开始行动了：  
- • 首先，leader 将项目拆分成 N 部分，由手下的 N 个 follower 并行推进  
  
- • 接下来，leader 需要总览全局，一一督促各位 follower 的完成进度  
  
- • 每名 follower 在完成手中的工作后，会同步告知 leader 这一情况  
  
- • 当 leader 发现全员都已完成任务后，会负责整合项目，进行整体交付  
  
注意，实现上面这个场景问题的关键在于，每名 follower 都是独立的个体，leader 一旦把项目拆分出去，自身对各模块的控制力度就相对减弱了，因此他需要有建立一个登记、上报和等待聚合的机制，持续等待直到聚齐所有 follower 的成果之后，再进汇总和交付：  
- • 建立登记机制：leader 需要清楚，当前一共有多少名 follower 参与协作. 最好能支持人员的增减变更能力，维护好一份动态的记录  
  
- • 建立上报机制：每当 follower 完成工作后，需要向 leader 同步这一情况.  
  
- • 建立等待聚合机制：当 leader 发现所有登记过的 follower 都已完成工作后，则可以进行最后的项目交付动作  
  
![](https://mmbiz.qpic.cn/mmbiz_png/3ic3aBqT2ibZtZnn18fvqvjJQUG3fic2miaib1ALqH9coUo0aHuQ3ch1KCSe6ibibE5AEJ8GExSicpPg19HzWASibh0ZHSw/640?wx_fmt=png "")  
  
   
## 1.2 手撸代码  
  
接下来基于编程的方式实现 1.1 小节中的场景问题  
  
由于这个问题涉及到不同 goroutine 之间的通信协作，我个人首先想到的就是使用 channel 进行实现：  
- • 建立登记机制：明确需要启动的子 goroutine 数量，创建对应容量的 channel  
  
- • 建立上报机制：每个子 goroutine 在退出前，会往 channel 中塞入一个信号量，标识自身的工作已经处理完成  
  
- • leader 进行工作汇总：主 goroutine 遍历 channel，直到接收到到对应于子 goroutine 数量的信号量后，流程才继续往下，否则会持续阻塞等待  
  
   
  
![](https://mmbiz.qpic.cn/mmbiz_png/3ic3aBqT2ibZtZnn18fvqvjJQUG3fic2miaibWzxhoVtZkhWH6mTJMe3tFsFIbP5oicwGQmgOibYw9bejpR7uBwt3UpAQ/640?wx_fmt=png "")  
  
   
  
基于上述思路，实现代码如下：  
```
func Test_waitGroup(t *testing.T) {
    // 并发任务数
    tasksNum := 10


    ch := make(chan struct{}, tasksNum)
    for i := 0; i < tasksNum; i++ {
        go func() {
            defer func() {
                ch <- struct{}{}
            }()
            // working
            <-time.After(time.Second)
        }()
    }


    // 等待 10 个 goroutine 完成任务
    for i := 0; i < tasksNum; i++ {
        <-ch
    }


    // do next
    // ...
}
```  
  
   
## 1.3 存在局限  
  
截止到 1.2 小节，我们看似已经实现了目标，但只能称得上“乞丐版”的实现. 回顾场景问题后，我们会发现上述实现中有两项局限性：  
- • 主 goroutine 需要在一开始就明确启动的子 goroutine 数量，从而建立好对应容量的 channel，以及设定执行 for 循环接收信号量的次数. 这样的设定不够灵活，因为在场景题中 leader 手下的 follower 数量可能会有实时增减  
  
- • channel 中的信号量消费是一次性的. 因此倘若存在多名 leader 想要同时使用聚合模式，这种场景是无法支持的. 除非创建多个 channel，分别给每名 leader 分配一个独立的 channel，每个 follower 完成工作后需要同时往多个 channel 中传递信号量. 这样的实现显得差强人意  
  
铺垫了这么久，就是为了引出我们今天的主角——golang 中的并发等待组工具 sync.WaitGroup. 下面我们就来聊聊，如何基于 WaitGroup 解决上诉场景问题.  
  
   
# 2 sync.WaitGroup 使用教程  
## 2.1 基本用法展示  
  
等待组工具 sync.WaitGroup ，本质上是一个并发计数器，暴露出来的核心方法有三个：  
- • WaitGroup.Add(n)：完成一次登记操作，使得 WaitGroup 中并发计数器的数值加上 n. 在使用场景中，WaitGroup.Add(n) 背后的含义是，注册并启动了 n 个子 goroutine  
  
- • WaitGroup.Done()：完成一次上报操作，使得 WaitGroup 中并发计数器的数值减 1. 在使用场景中，通常会在一个子 goroutine 退出前，会执行一次 WaitGroup.Done 方法  
  
- • WaitGroup.Wait()：完成聚合操作. 通常由主 goroutine 调用该方法，主 goroutine 会因此陷入阻塞，直到所有子 goroutine 都已经执行完成，使得 WaitGroup 并发计数器数值清零时，主 goroutine 才得以继续往下执行  
  
![](https://mmbiz.qpic.cn/mmbiz_png/3ic3aBqT2ibZtZnn18fvqvjJQUG3fic2miaib50jooLL4k5kbl7uoYU8JT85htmjrAtBQlsibNFmfYpn4Lz9EL2IU52w/640?wx_fmt=png "")  
  
![](https://mmbiz.qpic.cn/mmbiz_png/3ic3aBqT2ibZtZnn18fvqvjJQUG3fic2miaibPiabQwuusvR6Jouric0eEZ2xnTYnbLKbZNicaibs7Vyo83r3lQ2znWVWbQ/640?wx_fmt=png "")  
  
   
  
下面就给出 sync.WaitGroup 的使用示例：  
- • 首先声明一个等待组 wg  
  
- • 开启 for 循环，准备启动 10 个子 goroutine  
  
- • 在每次启动子 goroutine 之前，先在主 goroutine 中调用 WaitGroup.Add 方法，完成子 goroutine 的登记（注意，WaitGroup.Add 方法的调用时机应该在主 goroutine 而非子 goroutine 中，具体原因我们在本文 2.2 小节中给出）  
  
- • 依次启动子 goroutine，并在每个子 goroutine 中通过 defer 保证其退出前一定会调用一次 WaitGroup.Done 方法，完成上报动作，让 WaitGroup 中的计数器数值减 1  
  
- • 主 goroutine 启动好子 goroutine 后，调用 WaitGroup.Wait 方法，阻塞等待，直到所有子 goroutine 都执行过 WaitGroup.Done 方法，WaitGroup 计数器清零后，主 goroutine 才得以继续往下  
  
```
func Test_waitGroup(t *testing.T) {
    var wg sync.WaitGroup
    for i := 0; i < 10; i++ {
        wg.Add(1)
        go func() {
            defer wg.Done()
            <-time.After(time.Second)
        }()
    }


    wg.Wait()
}
```  
  
   
## 2.2 错误用法示警  
  
在使用 sync.WaitGroup 时，有两类错误操作是需要规避的：  
- • 需要保证添加计数器数值的 WaitGroup.Add 操作是在 WaitGroup.Wait 操作之前执行，否则可能出现逻辑问题，甚至导致程序 panic.  
  
这里给出一种反例展示如下：  
```
func Test_waitGroup(t *testing.T) {
    var wg sync.WaitGroup
    for i := 0; i < 10; i++ {
        go func() {
            wg.Add(1)
            defer wg.Done()
            <-time.After(time.Second)
        }()
    }


    wg.Wait()
}
```  
  
   
  
![](https://mmbiz.qpic.cn/mmbiz_png/3ic3aBqT2ibZtZnn18fvqvjJQUG3fic2miaiboibp8FOMxXDh5QtbRuR00ROWObibSkwh53gOcyhpazh8koNYb5NAFdZA/640?wx_fmt=png "")  
  
   
  
在上面的代码中，我们在子 goroutine 内部依次执行 WaitGroup.Add 和 WaitGroup.Done 方法，在主 goroutine 外部执行 WaitGroup.Wait 方法. 乍一看，Add 和 Done 成对执行没有问题，实则不然，这里存在两个问题：  
  
（1）由于子 goroutine 是异步启动的，所以有可能出现 Wait 方法先于 Add 方法执行，此时由于计数器值为 0，Wait 方法会被直接放行，导致产生预期之外的执行流程  
  
（2）在 WaitGroup 的使用中，需要遵循一个“轮次”的概念. 轮次的结束是在 WaitGroup 计数器被置为 0 的时刻，此时因 Wait 操作而陷入阻塞的一系列 goroutine 会得到一次被唤醒的机会. 在轮次终止的时候，如果再并发地执行 Add 操作，则会引发 panic. 关于这一点，本文 3.2 小节源码分析中会展开说明.  
  
   
- • 使用时，需要保证 WaitGroup 计数器数值始终是一个非负数. 即执行 Add 的数量需要大于等于 Done 的数量，否则也会引起 panic. 同样在本文 3.2 小节源码分析中会证明这一点.  
  
   
## 2.3 WaitGroup + channel 完成数据聚合  
  
沿着 1.1 小节的场景问题继续深挖. 我们说到，leader 需要在所有 follower 完成工作后进行项目整合. 因此 leader 光是知道 follower 已经完成工作这一事件还不够，还需要切实接收到来自 follower 传递的“工作成果”. 这部分内容就涉及到的 goroutine 之间的数据传递，这里我个人倾向于通过组合使用 WaitGroup 和 channel 的方式来完成工作.  
  
下面的内容比较主观，算是结合我的个人风格对并发编程中数据聚合实现方式的一种推演和探讨，大家如有其他想法，欢迎点评讨论.  
  
   
### 2.3.1 数据聚合版本 1.0  
  
![](https://mmbiz.qpic.cn/mmbiz_png/3ic3aBqT2ibZtZnn18fvqvjJQUG3fic2miaibKm4bSrGXMaM1VNBb9ufyRxmXbnQmMTEqHsKdIgdxqkowIMLaWoZKiaw/640?wx_fmt=png "")  
  
   
  
首先抛出一个略有瑕疵的实现版本 1.0：  
- • 创建一个用于数据传输的 channel：dataCh. dataCh 可以是无缓冲类型，因为后续会开启一个持续接收数据的读协程，写协程不会出现阻塞的情况  
  
- • 主 goroutine 中创建一个 slice：resp，用于承载聚合后的数据结果. 需要注意，slice 不是并发安全的数据结构，因此在往 slice 中写数据时需要保证是串行化进行的  
  
- • 异步启动一个读 goroutine，持续从 dataCh 中接收数据，然后将其追加到 resp slice 当中. 需要注意，读 goroutine 中通过这种 for range 的方式遍历 channel，只有在 channel 被关闭且内部数据被读完的情况下，遍历才会终止  
  
- • 基于 WaitGroup 的使用模式，启动多个子 goroutine，模拟任务的进行，并将处理完成的数据塞到 dataCh 当中供读 goroutine 接收和聚合  
  
- • 主 goroutine 通过 WaitGroup.Wait 操作，确保所有子 goroutine 都完成工作后，执行 dataCh 的关闭操作  
  
- • 主 goroutine 从读 goroutine 手中获取到聚合好数据的 resp slice，继续往下处理  
  
对应的实现源码如下：  
```
func Test_waitGroup(t *testing.T) {
    tasksNum := 10


    dataCh := make(chan interface{})
    resp := make([]interface{}, 0, tasksNum)
    // 启动读 goroutine
    go func() {
        for data := range dataCh {
            resp = append(resp, data)
        }
    }()


    // 保证获取到所有数据后，通过 channel 传递到读协程手中
    var wg sync.WaitGroup
    for i := 0; i < tasksNum; i++ {
        wg.Add(1)
        go func(ch chan<- interface{}) {
            defer wg.Done()
            ch <- time.Now().UnixNano()
        }(dataCh)
    }
    // 确保所有取数据的协程都完成了工作，才关闭 ch
    wg.Wait()
    close(dataCh)


    t.Logf("resp: %+v", resp)
}
```  
  
   
  
下面考验一下大家对并发编程的敏感度. 看完上述流程与代码之后，大家有没有找到其中存在的并发问题呢？  
  
这里就不卖关子了. 并发问题是存在的，问题点就在于，主 goroutine 在通过 WaitGroup.Wait 方法确保子 goroutine 都完成任务后，会关闭 dataCh ，并直接获取 resp slice 进行打印. 此时 dataCh 虽然关闭了，但是由于异步的不确定性，读 goroutine 可能还没来得及将所有数据都聚合到 resp slice 当中，因此主 goroutine 拿到的 resp slice 可能存在数据缺失.  
  
   
### 2.3.2 数据聚合版本 2.0  
  
![](https://mmbiz.qpic.cn/mmbiz_png/3ic3aBqT2ibZtZnn18fvqvjJQUG3fic2miaibUYvicA9WtFz5ibYEoCfpDNofNqrR6Y2V5JhQvSPz4EnqCzib2xvESzzibQ/640?wx_fmt=png "")  
  
   
  
在版本 1.0 的基础上对问题进行修复，提出版本 2.0 的方案.  
  
之前存在的问题是，主 goroutine 可能在读 goroutine 完成数据聚合前，就已经取用了 resp slice. 那么我们就额外启用一个用于标识读 goroutine 是否执行结束的 channel：stopCh 即可. 具体步骤包括：  
- • 主 goroutine 关闭 dataCh 之后，不是立即取用 resp slice，而是会先尝试从 stopCh 中读取信号，读取成功后，才继续往下  
  
- • 读 goroutine 在退出前，往 stopCh 中塞入信号量，让主 goroutine 能够感知到读 goroutine 处理完成这一事件  
  
这样处理之后，逻辑是严谨的，主 goroutine 能够保证取得的 resp slice 所拥有的完整数据.  
```
func Test_waitGroup(t *testing.T) {
    tasksNum := 10


    dataCh := make(chan interface{})
    resp := make([]interface{}, 0, tasksNum)
    stopCh := make(chan struct{}, 1)
    // 启动读 goroutine
    go func() {
        for data := range dataCh {
            resp = append(resp, data)
        }
        stopCh <- struct{}{}
    }()


    // 保证获取到所有数据后，通过 channel 传递到读协程手中
    var wg sync.WaitGroup
    for i := 0; i < tasksNum; i++ {
        wg.Add(1)
        go func(ch chan<- interface{}) {
            defer wg.Done()
            ch <- time.Now().UnixNano()
        }(dataCh)
    }
    // 确保所有取数据的协程都完成了工作，才关闭 ch
    wg.Wait()
    close(dataCh)


    // 确保读协程处理完成
    <-stopCh


    t.Logf("resp: %+v", resp)
}
```  
  
   
### 2.3.3 数据聚合版本 3.0  
  
![](https://mmbiz.qpic.cn/mmbiz_png/3ic3aBqT2ibZtZnn18fvqvjJQUG3fic2miaib2Tcrdgqb6xaoR9pyBGadF65JgbPLic3gGiaXcicpy1KuZgJ9ePXMeibJUA/640?wx_fmt=png "")  
  
版本 2.0 需要额外引入一个 stopCh，用于主 goroutine 和读 goroutine 之间的通信交互，看起来总觉得不够优雅. 下面我们就较真一下，针对于如何省去这个小小的 channel，进行版本 3.0 的方案探讨.  
  
下面是我个人觉得更优雅的一种实现方式. （版本 3.0 的这种实现方式也是我在参与第一份工作和当时的技术导师 devin 讨论这个问题时，由他提出来的实现思路. 这里留个小彩蛋，小小怀念一下当初的日子）：  
- • 同样创建一个无缓冲的 dataCh，用于聚合数据的传递  
  
- • 异步启动一个总览写流程的写 goroutine，在这个写 goroutine 中，基于 WaitGroup 使用模式，让写 goroutine 中进一步启动的子 goroutine 在完成工作后，将数据发送到 dataCh 当中  
  
- • 写 goroutine 基于 WaitGroup.Wait 操作，在确保所有子 goroutine 完成工作后，关闭 dataCh  
  
- • 接下来，让主 goroutine 同时扮演读 goroutine 的角色，通过 for range 的方式持续遍历接收 dataCh 当中的数据，将其填充到 resp slice  
  
- • 当写 goroutine 关闭 dataCh 后，主 goroutine 才能结束遍历流程，从而确保能够取得完整的 resp 数据  
  
   
  
下面是版本 3.0 的实现源码. 这种实现方式是不存在并发问题的，大家不妨细读一下，如发现有问题，欢迎批评指正.  
```
func Test_waitGroup(t *testing.T) {
    tasksNum := 10


    dataCh := make(chan interface{})
    // 启动写 goroutine，推进并发获取数据进程，将获取到的数据聚合到 channel 中
    go func() {
        // 保证获取到所有数据后，通过 channel 传递到读协程手中
        var wg sync.WaitGroup
        for i := 0; i < tasksNum; i++ {
            wg.Add(1)
            go func(ch chan<- interface{}) {
                defer wg.Done()
                ch <- time.Now().UnixNano()
            }(dataCh)
        }
        // 确保所有取数据的协程都完成了工作，才关闭 ch
        wg.Wait()
        close(dataCh)
    }()


    resp := make([]interface{}, 0, tasksNum)
    // 主协程作为读协程，持续读取数据，直到所有写协程完成任务，chan 被关闭后才会往下
    for data := range dataCh {
        resp = append(resp, data)
    }
    t.Logf("resp: %+v", resp)
}
```  
  
   
## 2.4 工程案例  
  
下面我们再结合实际的工程案例，看看 sync.WaitGroup 在优秀的开源项目中是如何被使用的.  
  
在分布式 KV 存储组件 etcd 中有涉及到对 WaitGroup 的使用. 在 etcd 的服务注册与发现模块中，使用到 sync.WaitGroup 进行 resolver watch 监听协程的生命周期控制，具体处理方式如下：  
- • 在 resolver 类中内置一个 sync.WaitGroup  
  
- • 在启动 resolver watch 监听协程前，先执行 WaitGroup.Add(1) ，登记了 watch 协程的运行情况  
  
- • 在 resolver watch 协程运行退出前，确保执行到 WaitGroup.Done ，告知 WaitGroup watch 协程已经退出，对等待组的计数器完成更新  
  
- • 在关闭 resolver 的 Close 方法中，调用 WaitGroup.Wait 方法，确保在 resolver watch 协程已退出的情况下，resolver 才能被关闭，从而避免出现协程泄漏问题，实现了 resolver 的优雅关闭策略  
  
有关 etcd resolver 使用到 sync.WaitGroup 的实现源码简化如下：  
```
func (b builder) Build(target gresolver.Target, cc gresolver.ClientConn, opts gresolver.BuildOptions) (gresolver.Resolver, error) {
    // ...


    r.wg.Add(1)
    go r.watch()
    return r, nil
}
```  
  
   
```
type resolver struct {
    // ...
    wg     sync.WaitGroup
}


func (r *resolver) watch() {
    defer r.wg.Done()
    // ...
}
// ...


func (r *resolver) Close() {
    // ...
    r.wg.Wait()
}
```  
  
   
  
如果大家对 etcd 服务注册与发现模块相关内容感兴趣的话，欢迎阅读我之前发表的文章——基于 etcd 实现 grpc 服务注册与发现.  
  
   
# 3 sync.WaitGroup 实现源码  
  
从第三章开始我们就正式进入喜闻乐见的源码走读环节.  
## 3.1 数据结构  
  
WaitGroup 位于 golang sync 包下，对应的类声明中包含了几个核心字段：  
- • noCopy：这是防拷贝标识，标记了 WaitGroup 不应该用于值传递  
  
- • state1：这是 WaitGroup 的核心字段，是一个无符号的64位整数，高32位是 WaitGroup 中并发计数器的数值，即当前 WaitGroup.Add 与 WaitGroup.Done 之间的差值；低 32 位标识了，当前有多少 goroutine 因 WaitGroup.Wait 操作而处于阻塞态，陷入阻塞态的原因是因为计数器的值没有清零，即 state1 字段高 32 位是一个正值  
  
- • state2：用于阻塞和唤醒 goroutine 的信号量  
  
![](https://mmbiz.qpic.cn/mmbiz_png/3ic3aBqT2ibZtZnn18fvqvjJQUG3fic2miaib8ibibKsS7HHicaCKu7nhrzT3OzW0UibV2SlL0ZgKwP0YpfsSciamVTFHXtA/640?wx_fmt=png "")  
  
   
```
type WaitGroup struct {
    // 防止值拷贝标记
    noCopy noCopy


    // 64 个 bit 组成的状态值，高 32 位标识了当前需要等待多少个 goroutine 执行了 WaitGroup.Add，还没执行 WaitGroup.Done；低 32 位表示了当前多少 goroutine 执行了 WaitGroup.Wait 操作陷入阻塞中了
    state1 uint64
    // 用于将 goroutine 阻塞和唤醒的信号量
    state2 uint32
}
```  
  
   
## 3.2 WaitGroup.Add  
  
![](https://mmbiz.qpic.cn/mmbiz_png/3ic3aBqT2ibZtZnn18fvqvjJQUG3fic2miaibhEd1fHNf3w6HIpVlnaTG5JlqQCovicPcpkca5J8Z5OdV0JUv0rkWohw/640?wx_fmt=png "")  
  
   
```
// 等待组计数器加 1
func (wg *WaitGroup) Add(delta int) {
    // 获取等待组的状态标识值，statep 指向 state1 的地址，semap 是用于阻塞挂起 goroutine 队列的标记值
    statep, semap := wg.state()
    // ...
    // state1 高 32 位加 1，标识执行任务数量加 1 
    state := atomic.AddUint64(statep, uint64(delta)<<32)
    // 取的是 state 高 32 位的值，代表有多少个 goroutine 在执行任务
    v := int32(state >> 32)
    // w 取的是 state 低 32 位的值，代表有多少个 goroutine 执行了 WaitGroup.Wait 在阻塞等待
    w := uint32(state)
    // ...
    // 不能出现负值的执行任务计数器
    if v < 0 {
        panic("sync: negative WaitGroup counter")
    }
    // 倘若存在 goroutine 在阻塞等待 WaitGroup.Wait，但是在执行 WaitGroup.Add 前，执行任务计数器的值为 0
    if w != 0 && delta > 0 && v == int32(delta) {
        panic("sync: WaitGroup misuse: Add called concurrently with Wait")
    }
    // 倘若当前没有 goroutine 在 Wait，或者任务执行计数器仍大于 0，则直接返回
    if v > 0 || w == 0 {
        return
    }
    // 在执行过 WaitGroup.Wait 操作的情况下，WaitGroup.Add 操作不应该并发执行，否则可能导致 panic
    if *statep != state {
        panic("sync: WaitGroup misuse: Add called concurrently with Wait")
    }
    // 将 state1 计数器置为 0，然后依次唤醒执行过 Wait 的 waiters
    *statep = 0
    for ; w != 0; w-- {
        runtime_Semrelease(semap, false, 0)
    }
}
```  
  
WaitGroup.Add 方法会给 WaitGroup 的计数器累加上一定的值，背后的含义是标识出当前有多少 goroutine 正在运行，需要由 WaitGroup.Done 操作完成数值的抵扣：  
- • 首先通过 WaitGroup.state 方法，获取到 WaitGroup 的 state1 和 state2 字段，分别将字段对应的地址赋给临时变量 statep 和 semap  
  
- • 调用 atomic.AddUint64，直接通过指针的方式直接在 WaitGroup.state1 的高 32 位基础上累加上 delta 的值  
  
- • 获取到 state1 高 32 位的值，赋值给局部变量 v，其含义是并发计数器的数值，即 WaitGroup.Add 和 WaitGroup.Done 之间的差值  
  
- • 获取到 state1 低 32 位的值，赋值给局部变量 w. 其含义是因执行 WaitGroup.Wait 操作而陷入阻塞态的 goroutine 数量  
  
- • 倘若 WaitGroup 计数器出现负值，直接 panic（ Done 不应该多于 Add ）  
  
- • 倘若首次 Add 操作是在有 goroutine 因 Wait 操作而陷入阻塞时才执行，抛出 panic（if w != 0 && delta > 0 && v == int32(delta) ）  
  
- • 倘若执行完 Add 操作后，WaitGroup 的计数器还是正值，则直接返回  
  
- • 倘若发现本次 Add 操作后， WaitGroup 计数器被清零了，则接下来需要依次把因 Wait 操作而陷入阻塞的 goroutine 唤醒. 在这期间，不允许再并发执行 Add 操作，否则会 panic  
  
- • 唤醒 goroutine 使用的方法是 runtime_Semrelease 方法，底层会执行 goready 操作，属于 goroutine 的被动调度模式  
  
   
## 3.3 WaitGroup.Done  
```
// Done decrements the WaitGroup counter by one.
func (wg *WaitGroup) Done() {
    wg.Add(-1)
}
```  
  
WaitGroup.Done 方法的含义是，当某个子 goroutine 执行完成后，需要对等待组进行上报，对计数器的数值执行减 1 操作.  
  
通过源码我们可以看到，WaitGroup.Done 方法内部执行了 WaitGroup.Add(-1) 操作，本质上是通过 Add 操作完成并发计数器数值减 1.  
  
WaitGroup.Done 通常在子 goroutine 内部执行，因此是可以并发调用的，但是使用的规则应该要保证，执行完本次 Done 操作后，并发计数器的数值仍然是大于等于 0 的，这样并发执行不会有问题.  
  
   
## 3.4 WaitGroup.state  
  
执行 WaitGroup.state 方法，会返回 WaitGroup 中的 state1 和 state2 字段，对应的含义我们在 3.1 小节数据结构篇章已经进行过说明.  
```
// state returns pointers to the state and sema fields stored within wg.state*.
func (wg *WaitGroup) state() (statep *uint64, semap *uint32) {
    // ...
    return &wg.state1, &wg.state2
    // ...
}
```  
  
   
## 3.5 WaitGroup.Wait  
  
![](https://mmbiz.qpic.cn/mmbiz_png/3ic3aBqT2ibZtZnn18fvqvjJQUG3fic2miaibvpqAtNxt4I1dGDiaoCtwN5JMMJFXiazzkOdWkaUVia2ibPzmOtwOoicXWKg/640?wx_fmt=png "")  
```
// Wait blocks until the WaitGroup counter is zero.
func (wg *WaitGroup) Wait() {
    // 获取 WaitGroup 状态字段的地址
    statep, semap := wg.state()
    // ...
    for {
        state := atomic.LoadUint64(statep)
        v := int32(state >> 32)
        w := uint32(state)
        // 倘若当前需要等待完成任务的计数器值为 0，则无需 wait 直接返回
        if v == 0 {
            // ...
            return
        }
        // wait 阻塞等待 waitGroup 的计数器加一，然后陷入阻塞
        if atomic.CompareAndSwapUint64(statep, state, state+1)atomic.CompareAndSwapUint64(statep, state, state+1) {
            // ...
            runtime_Semacquire(semap)
            // 从阻塞中回复，倘若前一轮 wait 操作还没结束，waitGroup 又被使用了，则会 panic
            if *statep != 0 {
                panic("sync: WaitGroup is reused before previous Wait has returned")
            }
            // ...
            return
        }
    }
}
```  
  
执行 WaitGroup.Wait 方法，会判断 WaitGroup 中的并发计数器数值是否为 0，如果不等于0，则当前 goroutine 会陷入阻塞态，直到计数器数值清零之后，才会被唤醒. 具体的执行流程如下：  
- • 执行 WaitGroup.state 方法，获取到 state1 和 state2 字段  
  
- • 走进 for 循环开启自旋流程  
  
- • 将 state1 高 32 位所存储的计数器数值赋给局部变量 v  
  
- • 将 state1 低 32 位所存储的阻塞 goroutine 数量赋给局部变量 w  
  
- • 倘若计数器数值 v 已经是 0 了，则无需阻塞 goroutine，直接返回即可  
  
- • 倘若计数器数值 v 大于 0，代表当前 goroutine 需要被阻塞挂起.  
  
- • 基于 cas，将 state1 低 32 位的数值加 1，标识有一个额外的 goroutine 需要阻塞挂起了  
  
- • 调用 runtime_Semacquire 方法，内部会通过 go park 操作，将当前 goroutine 阻塞挂起，属于被动调度模式  
  
- • 当 goroutine 从 runtime_Semacquire 方法走出来时，说明 WaitGroup 计数器已经被清零了.  
  
- • 在被唤醒的 goroutine 返回前，WaitGroup 不能被并发执行 Add 操作，否则会陷入 panic  
  
- • 被唤醒的 goroutine 正常返回，Wait 流程结束  
  
   
# 4 总结  
  
本期和大家一起分享了 Golang 中的并发等待组工具 sync.WaitGroup. 这种等待聚合的 goroutine 交互模式，为我们的并发编程工作提供了一种新的应对问题的思路.  
  
  
