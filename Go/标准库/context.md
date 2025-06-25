#  Golang context 实现原理   
原创 小徐先生  小徐先生的编程世界   2022-12-15 17:53  
  
## 0 前言  
  
context 是 golang 中的经典工具，主要在异步场景中用于实现并发协调以及对 goroutine 的生命周期控制. 除此之外，context 还兼有一定的数据存储能力. 本着知其然知其所以然的精神，本文和大家一起深入 context 源码一探究竟，较为细节地对其实现原理进行梳理.  
## 1 核心数据结构  
### 1.1 context.Context  
  
![](https://mmbiz.qpic.cn/mmbiz_png/3ic3aBqT2ibZvfwRgTAXo1RdShVNkHZHalqnGibXKxgD9owqhL6ZPBtpQxADvrGa5qKXvibs1Pib5we53dy1iaabuv0w/640?wx_fmt=png "")  
  
context数据结构  
```
type Context interface {
    Deadline() (deadline time.Time, ok bool)
    Done() <-chan struct{}
    Err() error
    Value(key any) any
}
```  
  
Context 为 interface，定义了四个核心 api：  
- • Deadline：返回 context 的过期时间；  
  
- • Done：返回 context 中的 channel；  
  
- • Err：返回错误；  
  
- • Value：返回 context 中的对应 key 的值.  
  
   
### 1.2 标准 error  
```
var Canceled = errors.New("context canceled")

var DeadlineExceeded error = deadlineExceededError{}

type deadlineExceededError struct{}

func (deadlineExceededError) Error() string   { return "context deadline exceeded" }
func (deadlineExceededError) Timeout() bool   { return true }
func (deadlineExceededError) Temporary() bool { return true
```  
- • Canceled：context 被 cancel 时会报此错误；  
  
- • DeadlineExceeded：context 超时时会报此错误.  
  
## 2 emptyCtx  
### 2.1 类的实现  
```
type emptyCtx int

func (*emptyCtx) Deadline() (deadline time.Time, ok bool) {
    return
}

func (*emptyCtx) Done() <-chan struct{} {
    return nil
}

func (*emptyCtx) Err() error {
    return nil
}

func (*emptyCtx) Value(key any) any {
    return 
}
```  
- • emptyCtx 是一个空的 context，本质上类型为一个整型；  
  
- • Deadline 方法会返回一个公元元年时间以及 false 的 flag，标识当前 context 不存在过期时间；  
  
- • Done 方法返回一个 nil 值，用户无论往 nil 中写入或者读取数据，均会陷入阻塞；  
  
- • Err 方法返回的错误永远为 nil；  
  
- • Value 方法返回的 value 同样永远为 nil.  
  
### 2.2 context.Background() & context.TODO()  
```
var (
    background = new(emptyCtx)
    todo       = new(emptyCtx)
)

func Background() Context {
    return background
}

func TODO() Context {
    return todo
}
```  
  
我们所常用的 context.Background() 和 context.TODO() 方法返回的均是 emptyCtx 类型的一个实例.  
## 3 cancelCtx  
### 3.1 cancelCtx 数据结构  
  
![](https://mmbiz.qpic.cn/mmbiz_png/3ic3aBqT2ibZvfwRgTAXo1RdShVNkHZHal10nWicjtGfpuhrAe1eXPFNmJMUgYctII58yAtkGM3m7FcnbDniaUyWuQ/640?wx_fmt=png "")  
  
cancelCtx数据结构  
```
type cancelCtx struct {
    Context
   
    mu       sync.Mutex            // protects following fields
    done     atomic.Value          // of chan struct{}, created lazily, closed by first cancel call
    children map[canceler]struct{} // set to nil by the first cancel call
    err      error                 // set to non-nil by the first cancel call
}

type canceler interface {
    cancel(removeFromParent bool, err error)
    Done() <-chan struct{}
}
```  
- • embed 了一个 context 作为其父 context. 可见，cancelCtx 必然为某个 context 的子 context；  
  
- • 内置了一把锁，用以协调并发场景下的资源获取；  
  
- • done：实际类型为 chan struct{}，即用以反映 cancelCtx 生命周期的通道；  
  
- • children：一个 set，指向 cancelCtx 的所有子 context；  
  
- • err：记录了当前 cancelCtx 的错误. 必然为某个 context 的子 context；  
  
### 3.2 Deadline 方法  
  
cancelCtx 未实现该方法，仅是 embed 了一个带有 Deadline 方法的 Context interface，因此倘若直接调用会报错.  
### 3.3 Done 方法  
  
![](https://mmbiz.qpic.cn/mmbiz_png/3ic3aBqT2ibZvfwRgTAXo1RdShVNkHZHal2PYOJJPIf6FMVCSqzVoFFnMvHIQuALvRg3CfutoztqKHaT3OdrnXcA/640?wx_fmt=png "")  
  
cancelCtx.Done  
```
func (c *cancelCtx) Done() <-chan struct{} {
    d := c.done.Load()
    if d != nil {
        return d.(chan struct{})
    }
    c.mu.Lock()
    defer c.mu.Unlock()
    d = c.done.Load()
    if d == nil {
        d = make(chan struct{})
        c.done.Store(d)
    }
    return d.(chan struct{})
}
```  
- • 基于 atomic 包，读取 cancelCtx 中的 chan；倘若已存在，则直接返回；  
  
- • 加锁后，在此检查 chan 是否存在，若存在则返回；（double check）  
  
- • 初始化 chan 存储到 aotmic.Value 当中，并返回.（懒加载机制）  
  
### 3.4 Err 方法  
```
func (c *cancelCtx) Err() error {
    c.mu.Lock()
    err := c.err
    c.mu.Unlock()
    return err
}
```  
- • 加锁；  
  
- • 读取 cancelCtx.err；  
  
- • 解锁；  
  
- • 返回结果.  
  
### 3.5 Value 方法  
```
func (c *cancelCtx) Value(key any) any {
    if key == &cancelCtxKey {
        return c
    }
    return value(c.Context, key)
}
```  
- • 倘若 key 特定值 &cancelCtxKey，则返回 cancelCtx 自身的指针；  
  
- • 否则遵循 valueCtx 的思路取值返回，具体见 2.1.6 小节.  
  
### 3.6 context.WithCancel()  
#### 3.6.1 context.WithCancel()  
```
func WithCancel(parent Context) (ctx Context, cancel CancelFunc) {
    if parent == nil {
        panic("cannot create context from nil parent")
    }
    c := newCancelCtx(parent)
    propagateCancel(parent, &c)
    return &c, func() { c.cancel(true, Canceled) }
}
```  
- • 校验父 context 非空；  
  
- • 注入父 context 构造好一个新的 cancelCtx；  
  
- • 在 propagateCancel 方法内启动一个守护协程，以保证父 context 终止时，该 cancelCtx 也会被终止；  
  
- • 将 cancelCtx 返回，连带返回一个用以终止该 cancelCtx 的闭包函数.  
  
#### 3.6.2 newCancelCtx  
```
func newCancelCtx(parent Context) cancelCtx {
    return cancelCtx{Context: parent}
}
```  
- • 注入父 context 后，返回一个新的 cancelCtx.  
  
#### 3.6.3 propagateCancel  
  
![](https://mmbiz.qpic.cn/mmbiz_png/3ic3aBqT2ibZvfwRgTAXo1RdShVNkHZHaliaDlicS0KjfkKRoflkGOImE2xamdv9H3AQuZUgib0ib78dticA5ic0S8f6RA/640?wx_fmt=png "")  
  
propagate流程  
```
func propagateCancel(parent Context, child canceler) {
    done := parent.Done()
    if done == nil {
        return // parent is never canceled
    }

    select {
    case <-done:
        // parent is already canceled
        child.cancel(false, parent.Err())
        return
    default:
    }

    if p, ok := parentCancelCtx(parent); ok {
        p.mu.Lock()
        if p.err != nil {
            // parent has already been canceled
            child.cancel(false, p.err)
        } else {
            if p.children == nil {
                p.children = make(map[canceler]struct{})
            }
            p.children[child] = struct{}{}
        }
        p.mu.Unlock()
    } else {
        atomic.AddInt32(&goroutines, +1)
        go func() {
            select {
            case <-parent.Done():
                child.cancel(false, parent.Err())
            case <-child.Done():
            }
        }()
    }
}
```  
  
propagateCancel 方法顾名思义，用以传递父子 context 之间的 cancel 事件：  
- • 倘若 parent 是不会被 cancel 的类型（如 emptyCtx），则直接返回；  
  
- • 倘若 parent 已经被 cancel，则直接终止子 context，并以 parent 的 err 作为子 context 的 err；  
  
- • 假如 parent 是 cancelCtx 的类型，则加锁，并将子 context 添加到 parent 的 children map 当中；  
  
- • 假如 parent 不是 cancelCtx 类型，但又存在 cancel 的能力（比如用户自定义实现的 context），则启动一个协程，通过多路复用的方式监控 parent 状态，倘若其终止，则同时终止子 context，并透传 parent 的 err.  
  
进一步观察 parentCancelCtx 是如何校验 parent 是否为 cancelCtx 的类型：  
```
func parentCancelCtx(parent Context) (*cancelCtx, bool) {
    done := parent.Done()
    if done == closedchan || done == nil {
        return nil, false
    }
    p, ok := parent.Value(&cancelCtxKey).(*cancelCtx)
    if !ok {
        return nil, false
    }
    pdone, _ := p.done.Load().(chan struct{})
    if pdone != done {
        return nil, false
    }
    return p, true
}
```  
- • 倘若 parent 的 channel 已关闭或者是不会被 cancel 的类型，则返回 false；  
  
- • 倘若以特定的 cancelCtxKey 从 parent 中取值，取得的 value 是 parent 本身，则返回 true. （基于 cancelCtxKey 为 key 取值时返回 cancelCtx 自身，是 cancelCtx 特有的协议）.  

  parentCancelCtx 不是对父 ctx 的类型校验，而是要向上追溯找到最近的一个 cancelCtx，然后将child添加到最近的 cancelCtx 的children当中. 这样可以节省一个守护协程的成本
#### 3.6.4 cancelCtx.cancel  
  
![](https://mmbiz.qpic.cn/mmbiz_png/3ic3aBqT2ibZvfwRgTAXo1RdShVNkHZHalkvwNxYrbVJsn2LorIG3ibESumuwIUTo8wEkWXf7sclgVYd33uQx0ticA/640?wx_fmt=png "")  
  
cancelCtx.cancel  
```
func (c *cancelCtx) cancel(removeFromParent bool, err error) {
    if err == nil {
        panic("context: internal error: missing cancel error")
    }
    c.mu.Lock()
    if c.err != nil {
        c.mu.Unlock()
        return // already canceled
    }
    c.err = err
    d, _ := c.done.Load().(chan struct{})
    if d == nil {
        c.done.Store(closedchan)
    } else {
        close(d)
    }
    for child := range c.children {
        // NOTE: acquiring the child's lock while holding parent's lock.
        child.cancel(false, err)
    }
    c.children = nil
    c.mu.Unlock()

    if removeFromParent {
        removeChild(c.Context, c)
    }
}
```  
- • cancelCtx.cancel 方法有两个入参，第一个 removeFromParent 是一个 bool 值，表示当前 context 是否需要从父 context 的 children set 中删除；第二个 err 则是 cancel 后需要展示的错误；  
  
- • 进入方法主体，首先校验传入的 err 是否为空，若为空则 panic；  
  
- • 加锁；  
  
- • 校验 cancelCtx 自带的 err 是否已经非空，若非空说明已被 cancel，则解锁返回；  
  
- • 将传入的 err 赋给 cancelCtx.err；  
  
- • 处理 cancelCtx 的 channel，若 channel 此前未初始化，则直接注入一个 closedChan，否则关闭该 channel；  
  
- • 遍历当前 cancelCtx 的 children set，依次将 children context 都进行 cancel；  
  
- • 解锁.  
  
- • 根据传入的 removeFromParent flag 判断是否需要手动把 cancelCtx 从 parent 的 children set 中移除.  
  
走进 removeChild 方法中，观察如何将 cancelCtx 从 parent 的 children set 中移除：  
```
func removeChild(parent Context, child canceler) {
    p, ok := parentCancelCtx(parent)
    if !ok {
        return
    }
    p.mu.Lock()
    if p.children != nil {
        delete(p.children, child)
    }
    p.mu.Unlock()
}
```  
- • 如果 parent 不是 cancelCtx，直接返回（因为只有 cancelCtx 才有 children set）   
  
- • 加锁；  
  
- • 从 parent 的 children set 中删除对应 child  
  
- • 解锁返回.  
  
## 4 timerCtx  
### 4.1 类  
  
![](https://mmbiz.qpic.cn/mmbiz_png/3ic3aBqT2ibZvfwRgTAXo1RdShVNkHZHal41XDibicmYv3qXYlDp6gMDA0mCB9f3h1BDsUqwpBIPEVwBQAVTadIE0A/640?wx_fmt=png "")  
  
timerCtx数据结构  
```
type timerCtx struct {
    cancelCtx
    timer *time.Timer // Under cancelCtx.mu.

    deadline time.Time
}
```  
  
timerCtx 在 cancelCtx 基础上又做了一层封装，除了继承 cancelCtx 的能力之外，新增了一个 time.Timer 用于定时终止 context；另外新增了一个 deadline 字段用于字段 timerCtx 的过期时间.  
### 4.2 timerCtx.Deadline()  
```
func (c *timerCtx) Deadline() (deadline time.Time, ok bool) {
    return c.deadline, true
}
```  
  
context.Context interface 下的 Deadline api 仅在 timerCtx 中有效，由于展示其过期时间.  
### 4.3 timerCtx.cancel  
```
func (c *timerCtx) cancel(removeFromParent bool, err error) {
    c.cancelCtx.cancel(false, err)
    if removeFromParent {
        removeChild(c.cancelCtx.Context, c)
    }
    c.mu.Lock()
    if c.timer != nil {
        c.timer.Stop()
        c.timer = nil
    }
    c.mu.Unlock()
}
```  
- • 复用继承的 cancelCtx 的 cancel 能力，进行 cancel 处理；  
  
- • 判断是否需要手动从 parent 的 children set 中移除，若是则进行处理  
  
- • 加锁；  
  
- • 停止 time.Timer  
  
- • 解锁返回.  
  
### 4.4 context.WithTimeout & context.WithDeadline  
```
func WithTimeout(parent Context, timeout time.Duration) (Context, CancelFunc) {
    return WithDeadline(parent, time.Now().Add(timeout))
}
```  
  
context.WithTimeout 方法用于构造一个 timerCtx，本质上会调用 context.WithDeadline 方法：  
```
func WithDeadline(parent Context, d time.Time) (Context, CancelFunc) {
    if parent == nil {
        panic("cannot create context from nil parent")
    }
    if cur, ok := parent.Deadline(); ok && cur.Before(d) {
        // The current deadline is already sooner than the new one.
        return WithCancel(parent)
    }
    c := &timerCtx{
        cancelCtx: newCancelCtx(parent),
        deadline:  d,
    }
    propagateCancel(parent, c)
    dur := time.Until(d)
    if dur <= 0 {
        c.cancel(true, DeadlineExceeded) // deadline has already passed
        return c, func() { c.cancel(false, Canceled) }
    }
    c.mu.Lock()
    defer c.mu.Unlock()
    if c.err == nil {
        c.timer = time.AfterFunc(dur, func() {
            c.cancel(true, DeadlineExceeded)
        })
    }
    return c, func() { c.cancel(true, Canceled) }
}
```  
- • 校验 parent context 非空；  
  
- • 校验 parent 的过期时间是否早于自己，若是，则构造一个 cancelCtx 返回即可；  
  
- • 构造出一个新的 timerCtx；  
  
- • 启动守护方法，同步 parent 的 cancel 事件到子 context；  
  
- • 判断过期时间是否已到，若是，直接 cancel timerCtx，并返回 DeadlineExceeded 的错误；  
  
- • 加锁；  
  
- • 启动 time.Timer，设定一个延时时间，即达到过期时间后会终止该 timerCtx，并返回 DeadlineExceeded 的错误；  
  
- • 解锁；  
  
- • 返回 timerCtx，已经一个封装了 cancel 逻辑的闭包 cancel 函数.  
  
## 5 valueCtx  
### 5.1 类  
  
![](https://mmbiz.qpic.cn/mmbiz_png/3ic3aBqT2ibZvfwRgTAXo1RdShVNkHZHalIVWfu4T9C1icgjPVgm72em5XEmkWMWcNeiatmNGGBerBtkcJ27XHCoVQ/640?wx_fmt=png "")  
  
  
valueCtx数据结构  
```
type valueCtx struct {
    Context
    key, val any
}
```  
- • valueCtx 同样继承了一个 parent context；  
  
- • 一个 valueCtx 中仅有一组 kv 对.  
  
### 5.2 valueCtx.Value()  
  
![](https://mmbiz.qpic.cn/mmbiz_png/3ic3aBqT2ibZvfwRgTAXo1RdShVNkHZHal2tHrS8XW75EIQC6BbgHbQchXplMw7nviagAUOhDKBGHQMqqYogcwZpg/640?wx_fmt=png "")  
  
valueCtx.Value  
```
func (c *valueCtx) Value(key any) any {
    if c.key == key {
        return c.val
    }
    return value(c.Context, key)
}
```  
- • 假如当前 valueCtx 的 key 等于用户传入的 key，则直接返回其 value；  
  
- • 假如不等，则从 parent context 中依次向上寻找.  
  
```
func value(c Context, key any) any {
    for {
        switch ctx := c.(type) {
        case *valueCtx:
            if key == ctx.key {
                return ctx.val
            }
            c = ctx.Context
        case *cancelCtx:
            if key == &cancelCtxKey {
                return c
            }
            c = ctx.Context
        case *timerCtx:
            if key == &cancelCtxKey {
                return &ctx.cancelCtx
            }
            c = ctx.Context
        case *emptyCtx:
            return nil
        default:
            return c.Value(key)
        }
    }
}
```  
- • 启动一个 for 循环，由下而上，由子及父，依次对 key 进行匹配；  
  
- • 其中 cancelCtx、timerCtx、emptyCtx 类型会有特殊的处理方式；  
  
- • 找到匹配的 key，则将该组 value 进行返回.  
  
### 5.3 valueCtx 用法小结  
  
阅读源码可以看出，valueCtx 不适合视为存储介质，存放大量的 kv 数据，原因有三：  
- • 一个 valueCtx 实例只能存一个 kv 对，因此 n 个 kv 对会嵌套 n 个 valueCtx，造成空间浪费；  
  
- • 基于 k 寻找 v 的过程是线性的，时间复杂度 O(N)；  
  
- • 不支持基于 k 的去重，相同 k 可能重复存在，并基于起点的不同，返回不同的 v. 由此得知，valueContext 的定位类似于请求头，只适合存放少量作用域较大的全局 meta 数据.  
  
### 5.4 context.WithValue()  
```
func WithValue(parent Context, key, val any) Context {
    if parent == nil {
        panic("cannot create context from nil parent")
    }
    if key == nil {
        panic("nil key")
    }
    if !reflectlite.TypeOf(key).Comparable() {
        panic("key is not comparable")
    }
    return &valueCtx{parent, key, val}
}
```  
- • 倘若 parent context 为空，panic；  
  
- • 倘若 key 为空 panic；  
  
- • 倘若 key 的类型不可比较，panic；  
  
- • 包括 parent context 以及 kv对，返回一个新的 valueCtx.  
  
# 实例
实现带有过期自动释放功能的单机锁
- 过期自动释放
- 解锁需要身份验证
- 基于 context, goroutine
## 方案I: 懒释放
![image.png](https://raw.githubusercontent.com/hmmm42/Picbed/main/obsidian/pictures20250625133943645.png)
## 方案II: 异步释放
```go
type ExpiredLock struct {
	mutex        sync.Mutex
	processMutex sync.Mutex
	owner        string
	stop         context.CancelFunc
}

func (e *ExpiredLock) Lock(expireAfter time.Duration) {
	e.processMutex.Lock()
	defer e.processMutex.Unlock()
	
	e.mutex.Lock()
	token := getCurrentOwner()
	e.owner = token
	
	if expireAfter <= 0 {
		return
	}
	
	ctx, cancel := context.WithTimeout(context.Background(), expireAfter)
	e.stop = cancel
	
	go func() {
		select {
		case <-time.After(expireAfter):
			err := e.unLock(token)
			if err != nil {
				panic(err)
			}
		case <-ctx.Done():
		}
	}()
}

func (e *ExpiredLock) Unlock() error {
	token := getCurrentOwner()
	return e.unLock(token)
}

func (e *ExpiredLock) unLock(token string) error {
	e.processMutex.Lock()
	defer e.processMutex.Unlock()
	
	if token != e.owner {
		return fmt.Errorf("cannot unlock: current owner %s does not match lock owner %s", getCurrentOwner(), e.owner)
	}
	
	e.owner = ""
	
	if e.stop != nil {
		e.stop()
	}
	
	e.mutex.Unlock()
	return nil
}

```