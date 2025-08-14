**精炼概括**：Channel 是一个线程安全的、基于**环形缓冲区**的队列。它通过**互斥锁**保证了并发安全，并使用**调度器**来管理等待的 Goroutine。**无缓冲**通道用于协程间的**同步**，**有缓冲**通道则用于协程间的**解耦**和**数据传递**。
#  Golang Channel 实现原理   
  
![](https://mmbiz.qpic.cn/mmbiz_png/3ic3aBqT2ibZvfwRgTAXo1RdShVNkHZHaliaCdialvlv2mKP7BhAicAYgGXhjHM11QIpUNRl8pj938QZrylOOHpcPTQ/640?wx_fmt=png "null")  
  
用过 go 的都知道 channel，无需多言，直接开整！  
## 1 核心数据结构  
  
![](https://mmbiz.qpic.cn/mmbiz_png/3ic3aBqT2ibZvfwRgTAXo1RdShVNkHZHal5lUA4QFlQJF8muLhNxWXCUcKvNeibTCicyuXU081nq6WkDDNFgxmjq1A/640?wx_fmt=png "")  
  
chan数据结构  
### 1.1 hchan  
```
type hchan struct {
    qcount   uint           // total data in the queue
    dataqsiz uint           // size of the circular queue
    buf      unsafe.Pointer // points to an array of dataqsiz elements
    elemsize uint16
    closed   uint32
    elemtype *_type // element type
    sendx    uint   // send index
    recvx    uint   // receive index
    recvq    waitq  // list of recv waiters
    sendq    waitq  // list of send waiters
    
    lock mutex
}
```  
  
hchan：channel 数据结构  
-  qcount：当前 channel 中存在多少个元素；  
  
-  dataqsize: 当前 channel 能存放的元素容量；  
  
-  ==buf：channel 中用于存放元素的环形缓冲区==；  
  
-  elemsize：channel 元素类型的大小；  
  
-  closed：标识 channel 是否关闭；  
  
-  elemtype：channel 元素类型；  
  
-  sendx：发送元素进入环形缓冲区的 index；  
  
-  recvx：接收元素所处的环形缓冲区的 index；  
  
-  recvq：因接收而陷入阻塞的协程队列；  
  
-  sendq：因发送而陷入阻塞的协程队列；  
  
### 1.2 waitq  
```
type waitq struct {
    first *sudog
    last  *sudog
}
```  
  
waitq：阻塞的协程队列  
-  first：队列头部  
  
-  last：队列尾部  
  
### 1.3 sudog  
```
type sudog struct {
    g *g

    next *sudog
    prev *sudog
    elem unsafe.Pointer // data element (may point to stack)

    isSelect bool

    c        *hchan 
}
```  
  
sudog：用于包装协程的节点  
-  g：goroutine，协程；  
  
-  next：队列中的下一个节点；  
  
-  prev：队列中的前一个节点；  
  
-  elem: 读取/写入 channel 的数据的容器;  
  
-  isSelect：标识当前协程是否处在 select 多路复用的流程中；  
  
-  c：标识与当前 sudog 交互的 chan.  
  
   
## 2 构造器函数  
  
![](https://mmbiz.qpic.cn/mmbiz_png/3ic3aBqT2ibZvfwRgTAXo1RdShVNkHZHaltgyFT3CVayaP9pplTJQGvBIKhrCbsKkY6YYiatEFVf0Wg5fxjuogKag/640?wx_fmt=png "")  
  
几种类型的 channel  
```
func makechan(t *chantype, size int) *hchan {
    elem := t.elem

    // ...
    mem, overflow := math.MulUintptr(elem.size, uintptr(size))
    if overflow || mem > maxAlloc-hchanSize || size < 0 {
        panic(plainError("makechan: size out of range"))
    }

    var c *hchan
    switch {
    case mem == 0:
        // Queue or element size is zero.
        c = (*hchan)(mallocgc(hchanSize, nil, true))
        // Race detector uses this location for synchronization.
        c.buf = c.raceaddr()
    case elem.ptrdata == 0:
        // Elements do not contain pointers.
        // Allocate hchan and buf in one call.
        c = (*hchan)(mallocgc(hchanSize+mem, nil, true))
        c.buf = add(unsafe.Pointer(c), hchanSize)
    default:
        // Elements contain pointers.
        c = new(hchan)
        c.buf = mallocgc(mem, elem, true)
    }

    c.elemsize = uint16(elem.size)
    c.elemtype = elem
    c.dataqsiz = uint(size)
    
    lockInit(&c.lock, lockRankHchan)

    return
}
```  
-  判断申请内存空间大小是否越界，mem 大小为 element 类型大小与 element 个数相乘后得到，仅当无缓冲型 channel 时，因个数为 0 导致大小为 0；  
  
-  根据类型，初始 channel，分为 无缓冲型、有缓冲元素为 struct 型、有缓冲元素为 pointer 型 channel;  
  
-  倘若为无缓冲型，则仅申请一个大小为默认值 96 的空间；  
  
-  如若有缓冲的 struct 型，则一次性分配好 96 + mem 大小的空间，并且调整 chan 的 buf 指向 mem 的起始位置；  
  
-  倘若为有缓冲的 pointer 型，则分别申请 chan 和 buf 的空间，两者无需连续；  
  
-  对 channel 的其余字段进行初始化，包括元素类型大小、元素类型、容量以及锁的初始化.  
  
## 3 写流程  
### 3.1 两类异常情况处理  
```
func chansend1(c *hchan, elem unsafe.Pointer) {
    chansend(c, elem, true, getcallerpc())
}

func chansend(c *hchan, ep unsafe.Pointer, block bool, callerpc uintptr) bool {
    if c == nil {
        gopark(nil, nil, waitReasonChanSendNilChan, traceEvGoStop, 2)
        throw("unreachable")
    }

    lock(&c.lock)

    if c.closed != 0 {
        unlock(&c.lock)
        panic(plainError("send on closed channel"))
    }
    
    // ...
```  
-  对于未初始化的 chan，写入操作会引发死锁；  
  
-  对于已关闭的 chan，写入操作会引发 panic.  
  
### 3.2 case1：写时存在阻塞读协程  
就是有一个goroutine 在等待接收数据， 确保了要么是无缓冲， 要么缓冲区为空
  
![](https://mmbiz.qpic.cn/mmbiz_png/3ic3aBqT2ibZvfwRgTAXo1RdShVNkHZHalTfhbUWG6lYPxb5geM0uH7yNRb2L5CXxzfnatadv6Zgib4AxpEHqF8Ug/640?wx_fmt=png "")  
  
直接写入阻塞读协程  
  
   
```
func chansend(c *hchan, ep unsafe.Pointer, block bool, callerpc uintptr) bool {
    // ...

    lock(&c.lock)

    // ...

    if sg := c.recvq.dequeue(); sg != nil {
        // Found a waiting receiver. We pass the value we want to send
        // directly to the receiver, bypassing the channel buffer (if any).
        send(c, sg, ep, func() { unlock(&c.lock) }, 3)
        return true
    }
    
    // ...
```  
-  加锁；  
  
-  从阻塞度协程队列中取出一个 goroutine 的封装对象 sudog；  
  
-  在 send 方法中，会基于 memmove 方法，直接将元素拷贝交给 sudog 对应的 goroutine；  
  
-  在 send 方法中会完成解锁动作.  
  
### 3.3 case2：写时无阻塞读协程但环形缓冲区仍有空间  
  
![](https://mmbiz.qpic.cn/mmbiz_png/3ic3aBqT2ibZvfwRgTAXo1RdShVNkHZHalexd6XKcoqKSBUoUQnkKbymY458YoKOrn8J2nmvdbxZwC9ohjOicc5rg/640?wx_fmt=png "")  
  
写入环形缓冲区  
```
func chansend(c *hchan, ep unsafe.Pointer, block bool, callerpc uintptr) bool {
    // ...
    lock(&c.lock)
    // ...
    if c.qcount < c.dataqsiz {
        // Space is available in the channel buffer. Enqueue the element to send.
        qp := chanbuf(c, c.sendx)
        typedmemmove(c.elemtype, qp, ep)
        c.sendx++
        if c.sendx == c.dataqsiz {
            c.sendx = 0
        }
        c.qcount++
        unlock(&c.lock)
        return true
    }

    // ...
}
```  
-  加锁；  
  
-  将当前元素添加到环形缓冲区 sendx 对应的位置；  
  
-  sendx++;  
  
-  qcount++;  
  
-  解锁，返回.  
  
### 3.4 case3：写时无阻塞读协程且环形缓冲区无空间  
  
![](https://mmbiz.qpic.cn/mmbiz_png/3ic3aBqT2ibZvfwRgTAXo1RdShVNkHZHalF0SY3ASfYoHzmoiaIY3sKOfz4cLGpRHc4sAZ39hKEkCEql4O1N4wz2g/640?wx_fmt=png "")  
  
阻塞写协程  
```go
func chansend(c *hchan, ep unsafe.Pointer, block bool, callerpc uintptr) bool {
    // ...
    lock(&c.lock)

    // ...
    gp := getg()
    mysg := acquireSudog()
    mysg.elem = ep
    mysg.g = gp
    mysg.c = c
    gp.waiting = mysg
    c.sendq.enqueue(mysg)
    
    atomic.Store8(&gp.parkingOnChan, 1)
    gopark(chanparkcommit, unsafe.Pointer(&c.lock), waitReasonChanSend, traceEvGoBlockSend, 2)
    // 会阻塞在这里, 直到有读协程调用 goready
    
    gp.waiting = nil
    closed := !mysg.success
    gp.param = nil
    mysg.c = nil
    releaseSudog(mysg)
    return true
}
```  
-  加锁；  
  
-  构造封装当前 goroutine 的 sudog 对象；  
  
-  完成指针指向，建立 sudog、goroutine、channel 之间的指向关系；  
  
-  把 sudog 添加到当前 channel 的阻塞写协程队列中；  
  
-  park 当前协程；  
  
-  倘若协程从 park 中被唤醒，则回收 sudog（sudog能被唤醒，其对应的元素必然已经被读协程取走）；  
- ! 如果唤醒时, 发现是因为 channel 被关闭才被唤醒, 则直接 panic
  
-  解锁，返回  
  
### 3.5 写流程整体串联  
  
![](https://mmbiz.qpic.cn/mmbiz_png/3ic3aBqT2ibZvfwRgTAXo1RdShVNkHZHalOGVPrpzAbEemKrksicEDjfMovicViacbWYnjyK017PrZj9lIfp9r1OeBA/640?wx_fmt=png "")  
  
写流程串联  
## 4 读流程  
### 4.1 异常 case1：读空 channel  
```
func chanrecv(c *hchan, ep unsafe.Pointer, block bool) (selected, received bool) {
    if c == nil {
        gopark(nil, nil, waitReasonChanReceiveNilChan, traceEvGoStop, 2)
        throw("unreachable")
    }
    // ...
}
```  
-  park 挂起，引起死锁；  
  
### 4.2 异常 case2：channel 已关闭且内部无元素  
```go
func chanrecv(c *hchan, ep unsafe.Pointer, block bool) (selected, received bool) {
  
    lock(&c.lock)

    if c.closed != 0 {
        if c.qcount == 0 {
            unlock(&c.lock)
            if ep != nil {
                typedmemclr(c.elemtype, ep)
            }
            // ep == nil 意味着没有容器接收 channel 
            // 例如 <-ch
            return true, false
        }
        // The channel has been closed, but the channel's buffer have data.
    } 

    // ...
```  
-  直接解锁返回即可  
  
### 4.3 case3：读时有阻塞的写协程  
  
![](https://mmbiz.qpic.cn/mmbiz_png/3ic3aBqT2ibZvfwRgTAXo1RdShVNkHZHalTr98gvVdDMla0Vb7vxHAwT4MK3R2TloJgDpeoJ4kuibs1XrDyE0tvVA/640?wx_fmt=png "")  
  
从阻塞写协程中读取  
```
func chanrecv(c *hchan, ep unsafe.Pointer, block bool) (selected, received bool) {
   
    lock(&c.lock)

    if sg := c.sendq.dequeue(); sg != nil {
        recv(c, sg, ep, func() { unlock(&c.lock) }, 3)
        return true, true
     }
     // ...
}
```  
-  加锁；  
  
-  从阻塞写协程队列中获取到一个写协程；  
  
-  倘若 channel 无缓冲区，则直接读取写协程元素，并唤醒写协程；  
  
-  倘若 channel 有缓冲区，则读取缓冲区头部元素，并将写协程元素写入缓冲区尾部后唤醒写写成；  
  
-  解锁，返回.  
  
   
### 4.4 case4：读时无阻塞写协程且缓冲区有元素  
  
![](https://mmbiz.qpic.cn/mmbiz_png/3ic3aBqT2ibZvfwRgTAXo1RdShVNkHZHalicLS8E93ScWkf4fsfSt6iaRfsZjcj4xLEbbcJMYrAFqX0jZfIThhKU8w/640?wx_fmt=png "")  
  
从环形缓冲区读取  
```
func chanrecv(c *hchan, ep unsafe.Pointer, block bool) (selected, received bool) {
    // ...
    lock(&c.lock)
    // ...
    if c.qcount > 0 {
        // Receive directly from queue
        qp := chanbuf(c, c.recvx)
        if ep != nil {
            typedmemmove(c.elemtype, ep, qp)
        }
        typedmemclr(c.elemtype, qp)
        c.recvx++
        if c.recvx == c.dataqsiz {
            c.recvx = 0
        }
        c.qcount--
        unlock(&c.lock)
        return true, true
    }
    // ...
```  
-  加锁；  
  
-  获取到 recvx 对应位置的元素；  
  
-  recvx++  
  
-  qcount--  
  
-  解锁，返回  
  
   
### 4.5 case5：读时无阻塞写协程且缓冲区无元素  
  
![](https://mmbiz.qpic.cn/mmbiz_png/3ic3aBqT2ibZvfwRgTAXo1RdShVNkHZHalZIEFfx1jzCY2Y8VMwtEeOicMCoT2qM5hK2r3eErOyIeeyBsY3G0ibHXA/640?wx_fmt=png "")  
  
阻塞读协程  
```
func chanrecv(c *hchan, ep unsafe.Pointer, block bool) (selected, received bool) {
   // ...
   lock(&c.lock)
   // ...
    gp := getg()
    mysg := acquireSudog()
    mysg.elem = ep
    gp.waiting = mysg
    mysg.g = gp
    mysg.c = c
    gp.param = nil
    c.recvq.enqueue(mysg)
    atomic.Store8(&gp.parkingOnChan, 1)
    gopark(chanparkcommit, unsafe.Pointer(&c.lock), waitReasonChanReceive, traceEvGoBlockRecv, 2)

    gp.waiting = nil
    success := mysg.success
    gp.param = nil
    mysg.c = nil
    releaseSudog(mysg)
    return true, success
}
```  
-  加锁；  
  
-  构造封装当前 goroutine 的 sudog 对象；  
  
-  完成指针指向，建立 sudog、goroutine、channel 之间的指向关系；  
  
-  把 sudog 添加到当前 channel 的阻塞读协程队列中；  
  
-  park 当前协程；  
  
-  倘若协程从 park 中被唤醒，则回收 sudog（sudog能被唤醒，其对应的元素必然已经被写入）；  
  
-  解锁，返回  
  
### 4.6 读流程整体串联  
  
![](https://mmbiz.qpic.cn/mmbiz_png/3ic3aBqT2ibZvfwRgTAXo1RdShVNkHZHalNcSib0wQr8hYDrKC8oSBjehE4F1E51vReJ7pv9yiaBS9ricJicWDibIAEmw/640?wx_fmt=png "")  
  
读流程串联  
## 5 阻塞与非阻塞模式  
  
在上述源码分析流程中，均是以阻塞模式为主线进行讲述，忽略非阻塞模式的有关处理逻辑. 此处阐明两个问题：  
-  非阻塞模式下，流程逻辑有何区别？  
-  何时会进入非阻塞模式？  
  
### 5.1 非阻塞模式逻辑区别  
  
非阻塞模式下，读/写 channel 方法通过一个 bool 型的响应参数，用以标识是否读取/写入成功.  
-  所有需要使得当前 goroutine 被挂起的操作，在非阻塞模式下都会返回 false；  
  
-  所有是的当前 goroutine 会进入死锁的操作，在非阻塞模式下都会返回 false；  
  
-  所有能立即完成读取/写入操作的条件下，非阻塞模式下会返回 true.  
  
### 5.2 何时进入非阻塞模式  
  
默认情况下，读/写 channel 都是阻塞模式，只有在 select 语句组成的多路复用分支中，与 channel 的交互会变成非阻塞模式：  
```
ch := make(chan int)
select{
  case <- ch:
  default:
}
```  
### 5.3 代码一览  
```
func selectnbsend(c *hchan, elem unsafe.Pointer) (selected bool) {
    return chansend(c, elem, false, getcallerpc())
}

func selectnbrecv(elem unsafe.Pointer, c *hchan) (selected, received bool) {
    return chanrecv(c, elem, false)
}
```  
  
在 select 语句包裹的多路复用分支中，读和写 channel 操作会被汇编为 selectnbrecv 和 selectnbsend 方法，底层同样复用 chanrecv 和 chansend 方法，但此时由于第三个入参 block 被设置为 false，导致后续会走进非阻塞的处理分支.  
## 6 两种读 channel 的协议  
  
读取 channel 时，可以根据第二个 bool 型的返回值用以判断当前 channel 是否已处于关闭状态：  
```
ch := make(chan int, 2)
got1 := <- ch
got2,ok := <- ch
```  
  
实现上述功能的原因是，两种格式下，读 channel 操作会被汇编成不同的方法：  
```
func chanrecv1(c *hchan, elem unsafe.Pointer) {
    chanrecv(c, elem, true)
}

//go:nosplit
func chanrecv2(c *hchan, elem unsafe.Pointer) (received bool) {
    _, received = chanrecv(c, elem, true)
    return
}
```  
## 7 关闭  
  
![](https://mmbiz.qpic.cn/mmbiz_png/3ic3aBqT2ibZvfwRgTAXo1RdShVNkHZHal6qVUicAZM73eat8Fyj7ICWmbdybLmMfEHEibrXZ6relibCY5kFXMABbkg/640?wx_fmt=png "")  
  
关闭 channel 流程  
```
func closechan(c *hchan) {
    if c == nil {
        panic(plainError("close of nil channel"))
    }

    lock(&c.lock)
    if c.closed != 0 {
        unlock(&c.lock)
        panic(plainError("close of closed channel"))
    }

    c.closed = 1

    var glist gList
    // release all readers
    for {
        sg := c.recvq.dequeue()
        if sg == nil {
            break
        }
        if sg.elem != nil {
            typedmemclr(c.elemtype, sg.elem)
            sg.elem = nil
        }
        gp := sg.g
        gp.param = unsafe.Pointer(sg)
        sg.success = false
        glist.push(gp)
    }

    // release all writers (they will panic)
    for {
        sg := c.sendq.dequeue()
        if sg == nil {
            break
        }
        sg.elem = nil
        gp := sg.g
        gp.param = unsafe.Pointer(sg)
        sg.success = false
        glist.push(gp)
    }
    unlock(&c.lock)

    // Ready all Gs now that we've dropped the channel lock.
    for !glist.empty() {
        gp := glist.pop()
        gp.schedlink = 0
        goready(gp, 3)
```  
-  关闭未初始化过的 channel 会 panic；  
  
-  加锁；  
  
-  重复关闭 channel 会 panic；  
  
-  将阻塞读协程队列中的协程节点统一添加到 glist；  
  
-  将阻塞写协程队列中的协程节点统一添加到 glist；  
  
-  **唤醒** glist 当中的所有协程.  
  
# 实例
实现一个支持并发的 Map，它具备$O(1)$的插入、查询操作，并且在查询的键不存在时能够阻塞等待，直到键被插入或等待超时。
```go
type ConcurrentMap[K comparable, V any] struct {
	sync.Mutex
	mp      map[K]V
	keyToCh map[K]chan struct{}
}

func NewConcurrentMap[K comparable, V any]() *ConcurrentMap[K, V] {
	return &ConcurrentMap[K, V]{
		mp:      make(map[K]V),
		keyToCh: make(map[K]chan struct{}),
	}
	// Mutex 是结构体, 不需要初始化
}

func (m *ConcurrentMap[K, V]) Put(k K, v V) {
	m.Lock()
	defer m.Unlock()
	m.mp[k] = v
	
	ch, ok := m.keyToCh[k]
	if !ok {
		return
	}
	//思路一: 直接删除key
	//close(ch) // 唤醒所有阻塞中的读协程
	//delete(m.keyToCh, k)
	
	//思路二: 多路复用
	//每次select只会执行一个分支的内容
	select {
	case <-ch:
		return
	default:
		close(ch)
	}
	
	//思路三: 包装ch, 加上sync.Once
}

func (m *ConcurrentMap[K, V]) Get(k K, maxWaitingDuration time.Duration) (V, error) {
	m.Lock()
	v, ok := m.mp[k]
	if ok {
		m.Unlock()
		return v, nil
	}
	
	ch, ok := m.keyToCh[k]
	if !ok {
		ch = make(chan struct{})
		m.keyToCh[k] = ch
	}
	
	m.Unlock()
	select {
	case <-time.After(maxWaitingDuration):
		var zero V
		return zero, errors.New("timeout")
	case <-ch:
	}
	
	m.Lock()
	v = m.mp[k]
	m.Unlock()
	return v, nil
}

```