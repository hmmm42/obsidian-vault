#  Golang 垃圾回收源码走读   
原创 小徐先生1212  小徐先生的编程世界   2023-02-17 20:21  
  
# 0 前言  
  
近期在和大家一起探讨 Golang 内存管理机制相关的内容.  
  
此前分别介绍了 Golang 内存模型及分配机制和 Golang 的垃圾回收原理有关的内容. 本篇会基于源码走读的方式，对Golang 垃圾回收的理论进行论证和补充. 本文走读的源码版本为 Golang 1.19.  
  
由于内容之间具有强关联性，建议大家先完成前两篇内容的阅读，再开启本篇的学习.  
  
   
# 1 源码导读  
## 1.1 源码框架  
  
首先给出整体的源码走读框架，供大家总览全局，避免晕车.  
  
![](https://mmbiz.qpic.cn/mmbiz_png/3ic3aBqT2ibZu8WccNVUMwlnMQBKA4T5pPHhPjN5VicO9eObIicfakEr6mScMcmfS8nKGMmhVc3ufGahwLQfnLRUIg/640?wx_fmt=png "")  
## 1.2 文件位置  
  
GC中各子流程聚焦于不同源码文件中，目录供大家一览，感兴趣可以连贯阅读.  
  
<table><thead style="line-height: 1.75;background: rgba(0, 0, 0, 0.05);font-weight: bold;color: rgb(63, 63, 63);"><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;"><strong style="line-height: 1.75;color: rgb(15, 76, 129);">流程</strong></td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;"><strong style="line-height: 1.75;color: rgb(15, 76, 129);">文件</strong></td></tr></thead><tbody><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">标记准备</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime/mgc.go</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">调步策略</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime/mgcpacer.go</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">并发标记</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime/mgcmark.go</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">清扫流程</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime/msweep.go</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">位图标识</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime/mbitmap.go</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">触发屏障</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime/mbwbuf.go</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">内存回收</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime/mgcscavenge.go</td></tr></tbody></table>  
  
   
# 2 触发GC  
  
下面顺沿源码框架，开启走读流程. 本章首先聊聊，GC阶段是如何被触发启动的.  
  
![](https://mmbiz.qpic.cn/mmbiz_png/3ic3aBqT2ibZu8WccNVUMwlnMQBKA4T5pPBY6QWOTkUCOfJFj6HXmkmCLLSjic8wuO7wCqOW40FZ2FGqgtQ0KicfBw/640?wx_fmt=png "")  
  
   
## 2.1 触发GC类型  
  
触发 GC 的事件类型可以分为如下三种：  
  
<table><thead style="line-height: 1.75;background: rgba(0, 0, 0, 0.05);font-weight: bold;color: rgb(63, 63, 63);"><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;"><strong style="line-height: 1.75;color: rgb(15, 76, 129);">类型</strong></td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;"><strong style="line-height: 1.75;color: rgb(15, 76, 129);">触发事件</strong></td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;"><strong style="line-height: 1.75;color: rgb(15, 76, 129);">校验条件</strong></td></tr></thead><tbody><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">gcTriggerHeap</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">分配对象时触发</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">堆已分配内存达到阈值</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">gcTriggerTime</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">由 forcegchelper 守护协程定时触发</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">每2分钟触发一次</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">gcTriggerCycle</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">用户调用 runtime.GC 方法</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">上一轮 GC 已结束</td></tr></tbody></table>  
  
   
  
在触发GC时，会通过 gcTrigger.test 方法，结合具体的触发事件类型进行触发条件的校验，校验条件展示于上表，对应的源码如下：  
```
type gcTriggerKind int


const (
    // 根据堆分配内存情况，判断是否触发GC
    gcTriggerHeap gcTriggerKind = iota
    // 定时触发GC
    gcTriggerTime
    // 手动触发GC
    gcTriggerCycle
}


func (t gcTrigger) test() bool {
    // ...
    switch t.kind {
    case gcTriggerHeap:
        // ...
        trigger, _ := gcController.trigger()
        return atomic.Load64(&gcController.heapLive) >= trigger
    case gcTriggerTime:
        if gcController.gcPercent.Load() < 0 {
            return false
        }
        lastgc := int64(atomic.Load64(&memstats.last_gc_nanotime))
        return lastgc != 0 && t.now-lastgc > forcegcperiod
    case gcTriggerCycle:
        // ...
        return int32(t.n-work.cycles) > 0
    }
    return true
}
```  
  
   
## 2.2 定时触发GC  
  
定时触发 GC 的源码方法及文件如下表所示：  
  
<table><thead style="line-height: 1.75;background: rgba(0, 0, 0, 0.05);font-weight: bold;color: rgb(63, 63, 63);"><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;"><strong style="line-height: 1.75;color: rgb(15, 76, 129);">方法</strong></td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;"><strong style="line-height: 1.75;color: rgb(15, 76, 129);">文件</strong></td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;"><strong style="line-height: 1.75;color: rgb(15, 76, 129);">作用</strong></td></tr></thead><tbody><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">init</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime/proc.go</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">开启一个 forcegchelper 协程</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">forcegchelper</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime/proc.go</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">循环阻塞挂起+定时触发 gc</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">main</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime/proc.go</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">调用 sysmon 方法</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">sysmon</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime/proc.go</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">定时唤醒 forcegchelper，从而触发 gc</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">gcTrigger.test</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime/mgc.go</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">校验是否满足 gc 触发条件</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">gcStart</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime/mgc.go</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">标记准备阶段主流程方法</td></tr></tbody></table>  
  
   
  
（1）启动定时触发协程并阻塞等待  
  
runtime 包初始化的时候，即会异步开启一个守护协程，通过 for 循环 + park 的方式，循环阻塞等待被唤醒.  
  
当被唤醒后，则会调用 gcStart 方法进入标记准备阶段，尝试开启新一轮 GC，此时触发 GC 的事件类型正是 gcTriggerTime（定时触发）.  
  
在 gcStart 方法内部，还会通过 gcTrigger.test 方法进一步校验触发GC的条件是否满足，留待第3章再作展开.  
```
// runtime 包下的全局变量
var  forcegc   forcegcstate


type forcegcstate struct {
    lock mutex
    g    *g
    idle uint3


func init() {
    go forcegchelper()
}


func forcegchelper() {
    forcegc.g = getg()
    lockInit(&forcegc.lock, lockRankForcegc)
    for {
        lock(&forcegc.lock)
        // ...
        atomic.Store(&forcegc.idle, 1)
        // 令 forcegc.g 陷入被动阻塞，g 的状态会设置为 waiting，当达成 gc 条件时，g 的状态会被切换至 runnable，方法才会向下执行
        goparkunlock(&forcegc.lock, waitReasonForceGCIdle, traceEvGoBlock, 1)
        // g 被唤醒了，则调用 gcStart 方法真正开启 gc 主流程
        gcStart(gcTrigger{kind: gcTriggerTime, now: nanotime()})
    }
}
```  
  
   
  
（2）唤醒定时触发协程  
  
runtime 包下的 main 函数会通过 systemstack 操作切换至 g0（g0 是 Golang GMP 模型中的概念，如有疑惑，可参见我之前的文章：Golang GMP 原理），并调用 sysmon 方法，轮询尝试将 forcegchelper 协程添加到 gList 中，并在 injectglist 方法内将其唤醒：  
```
func main() {
    // ...
    systemstack(func() {
        newm(sysmon, nil, -1)
    })   
    // ...
}
```  
  
   
```
func sysmon() {
    // ...
    for { 
        // 通过 gcTrigger.test 方法检查是否需要发起 gc，触发类型为 gcTriggerTime：定时触发
        if t := (gcTrigger{kind: gcTriggerTime, now: now}); t.test() && atomic.Load(&forcegc.idle) != 0 {     
            lock(&forcegc.lock)
            forcegc.idle = 0
            var list gList
            // 需要发起 gc，则将 forcegc.g 注入 list 中, injectglist 方法内部会执行唤醒操作
            list.push(forcegc.g)
            injectglist(&list)
            unlock(&forcegc.lock)
        }
        // ...
    }
}
```  
  
   
  
（3）定时触发GC条件校验  
  
在 gcTrigger.test 方法中，针对 gcTriggerTime 类型的触发事件，其校验条件则是触发时间间隔达到 2分钟以上.  
```
// 单位 nano，因此实际值为 120s = 2min
var forcegcperiod int64 = 2 * 60 * 1e9


func (t gcTrigger) test() bool {
    // ...
    switch t.kind {
    // ...
    // 每 2 min 发起一轮 gc
    case gcTriggerTime:
        // ...
        lastgc := int64(atomic.Load64(&memstats.last_gc_nanotime))
        return lastgc != 0 && t.now-lastgc > forcegcperiod
    // ...
    }
    return true
}
```  
  
   
## 2.3 对象分配触发GC  
  
该流程源码方法及文件如下表所示：  
  
<table><thead style="line-height: 1.75;background: rgba(0, 0, 0, 0.05);font-weight: bold;color: rgb(63, 63, 63);"><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;"><strong style="line-height: 1.75;color: rgb(15, 76, 129);">方法</strong></td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;"><strong style="line-height: 1.75;color: rgb(15, 76, 129);">文件</strong></td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;"><strong style="line-height: 1.75;color: rgb(15, 76, 129);">作用</strong></td></tr></thead><tbody><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">mallocgc</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime/malloc.go</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">分配对象主流程方法</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">gcTrigger.test</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime/mgc.go</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">校验是否满足 gc 触发条件</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">gcStart</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime/mgc.go</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">标记准备阶段主流程方法</td></tr></tbody></table>  
  
在分配对象的malloc方法中，倘若满足如下两个条件之一，都会发起一次触发GC的尝试：  
- • 需要初始化一个大小超过32KB的大对象  
  
- • 待初始化对象在mcache中对应spanClass的mspan空间已用尽（如对有关概念存在疑惑，请优先阅读我的文章：Golang内存模型与分配机制）  
  
此时触发事件类型为gcTriggerHeap，并在调用gcStart方法的内部执行gcTrigger.test进行条件检查.  
  
   
  
（1）对象分配触发GC  
  
mallocgc 是分配对象的主流程方法：  
```
func mallocgc(size uintptr, typ *_type, needzero bool) unsafe.Pointer {
    // ...
    shouldhelpgc := false
    // ...
    if size <= maxSmallSize {
        if noscan && size < maxTinySize {
            // ...
            if v == 0 {
                // 倘若 mcache 中对应 spanClass 的 mspan 已满，置 true
                v, span, shouldhelpgc = c.nextFree(tinySpanClass)
            }
            // ...
        } else {
            // ...
            if v == 0 {
                // 倘若 mcache 中对应 spanClass 的 mspan 已满，置 true
                v, span, shouldhelpgc = c.nextFree(spc)
            }
            // ...
        }
    } else {
        // 申请大小大于 32KB 的大对象，直接置为 true
        shouldhelpgc = true
        // ...
    }


    // ...
    // 尝试触发 gc，类型为 gcTriggerHeap，触发校验逻辑同样位于 gcTrigger.test 方法中
    if shouldhelpgc {
        if t := (gcTrigger{kind: gcTriggerHeap}); t.test() {
            gcStart(t)
        }
    }


   // ...
}
```  
  
   
  
（2）校验GC触发条件  
  
在 gcTrigger.test 方法中，针对 gcTriggerHeap 类型的触发事件，其校验条件是判断当前堆已使用内存是否达到阈值. 此处的堆内存阈值会在上一轮GC结束时进行设定，具体内容将在本文6.4小节详细讨论.  
```
func (t gcTrigger) test() bool {
    // ...
    switch t.kind {
    case gcTriggerHeap:      
        trigger, _ := gcController.trigger()
        // 倘若堆中已使用的内存大小达到了阈值，则会真正执行 gc
        return atomic.Load64(&gcController.heapLive) >= trigger
    // ...
    }
    return true
}
```  
  
   
## 2.3 手动触发GC  
  
最后一种触发的GC形式是手动触发，入口位于 runtime 包的公共方法：runtime.GC  
  
<table><thead style="line-height: 1.75;background: rgba(0, 0, 0, 0.05);font-weight: bold;color: rgb(63, 63, 63);"><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;"><strong style="line-height: 1.75;color: rgb(15, 76, 129);">方法</strong></td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;"><strong style="line-height: 1.75;color: rgb(15, 76, 129);">文件</strong></td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;"><strong style="line-height: 1.75;color: rgb(15, 76, 129);">作用</strong></td></tr></thead><tbody><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">GC</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime/mgc.go</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">手动触发GC主流程方法</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">gcStart</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime/mgc.go</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">标记准备阶段主流程方法</td></tr></tbody></table>  
  
用户手动触发 GC时，事件类型为 gcTriggerCycle.  
```
func GC() {
    // ...
    gcStart(gcTrigger{kind: gcTriggerCycle, n: n + 1})
    // ...
}
```  
  
针对这种类型的校验条件是，上一轮GC已经完成，此时能够开启新一轮GC任务.  
```
func (t gcTrigger) test() bool {
    // ...
    switch t.kind {
    // ...
    case gcTriggerCycle:
        return int32(t.n-work.cycles) > 0
    }
    return true
}
```  
  
   
# 3 标记准备  
  
![](https://mmbiz.qpic.cn/mmbiz_png/3ic3aBqT2ibZu8WccNVUMwlnMQBKA4T5pPC1oU6hh9nNb86jMBHoPT6cpsh05ygucxr2KtpHVWvVXiaNn4XibeTTVQ/640?wx_fmt=png "")  
  
   
  
本章开始步入标记准备阶段的内容探讨中，本章会揭秘屏障机制以及 STW 的底层实现，所涉及的源码方法及文件位置如下表所示：  
  
<table><thead style="line-height: 1.75;background: rgba(0, 0, 0, 0.05);font-weight: bold;color: rgb(63, 63, 63);"><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;"><strong style="line-height: 1.75;color: rgb(15, 76, 129);">方法</strong></td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;"><strong style="line-height: 1.75;color: rgb(15, 76, 129);">文件</strong></td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;"><strong style="line-height: 1.75;color: rgb(15, 76, 129);">作用</strong></td></tr></thead><tbody><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">gcStart</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime/mgc.go</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">标记准备阶段主流程方法</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">gcBgMarkStartWorkers</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime/mgc.go</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">批量启动标记协程 ，数量对应于 P 的个数</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">gcBgMarkWorker</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime/mgc.go</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">标记协程主流程方法，启动之初会先阻塞挂起，待被唤醒后真正执行任务</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">stopTheWorldWithSema</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime/mgc.go</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">即STW，停止P.</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">gcControllerState.startCycle</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime/mgcspacer.go</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">限制标记协程执行频率，目标是令标记协程对CPU的占用率趋近于 25%</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">setGCPhase</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime/mgc.go</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">更新GC阶段. 当为标记阶段（GCMark）时会启用混合写屏障</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">gcMarkTinyAllocs</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime/mgc.go</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">标记 mcache 中的 tiny 对象</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">startTheWorldWithSema</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime/mgc.go</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">与STW相反，会重新唤醒各个P</td></tr></tbody></table>  
  
   
## 3.1 主流程  
  
gcStart 是标记准备阶段的主流程方法，方法中完成的工作包括：  
- • 再次检查GC触发条件是否达成  
  
- • 异步启动对应于P数量的标记协程  
  
- • Stop the world  
  
- • 控制标记协程数量和执行时长，使得CPU占用率趋近25%  
  
- • 设置GC阶段为GCMark，开启混合混合写屏障  
  
- • 标记mcache中的tiny对象  
  
- • Start the world  
  
```go
func gcStart(trigger gcTrigger) {
    // ...
    // 检查是否达到 GC 条件，会根据 trigger 类型作 dispatch，常见的包括堆内存大小、GC 时间间隔、手动触发的类型
    for trigger.test() && sweepone() != ^uintptr(0) {
        sweep.nbgsweep++
    }
    
    // 上锁
    semacquire(&work.startSema)
    // 加锁 double check
    if !trigger.test() {
        semrelease(&work.startSema)
        return
    }
    
    // ...
    // 由于进入了 GC 模式，会根据 P 的数量启动多个 GC 并发标记协程，但是会先阻塞挂起，等待被唤醒
    gcBgMarkStartWorkers()
    
    // ...
    // 切换到 g0，执行 Stop the world 操作
    systemstack(stopTheWorldWithSema)
    // ...
    
    // 限制标记协程占用 CPU 时间片的比例为趋近 25%
    gcController.startCycle(now, int(gomaxprocs), trigger)
     
    // 设置GC阶段为_GCmark，启用混合写屏障
    setGCPhase(_GCmark)


    // ...
    // 对 mcache 中的 tiny 对象进行标记
    gcMarkTinyAllocs()


    // 切换至 g0，重新 start the world
    systemstack(func() {
        now = startTheWorldWithSema(trace.enabled)
       // ...
    })
    // ...
}
```  
  
   
## 3.2 启动标记协程  
  
gcBgMarkStartWorkers方法中启动了对应于 P 数量的并发标记协程，并且通过notetsleepg的机制，使得for循环与gcBgMarkWorker内部形成联动节奏，确保每个P都能分得一个gcBgMarkWorker标记协程.  
```
func gcBgMarkStartWorkers() {
    // 开启对应于 P 个数标记协程，但是内部将 g 添加到全局的 pool 中，并通过 gopark 阻塞挂起
    for gcBgMarkWorkerCount < gomaxprocs {
        go gcBgMarkWorker()
        // 挂起，等待 gcBgMarkWorker 方法中完成标记协程与 P 的绑定后唤醒
        notetsleepg(&work.bgMarkReady, -1)
        noteclear(&work.bgMarkReady)
        
        gcBgMarkWorkerCount++
    }
}
```  
  
   
  
gcBgMarkWorker 方法中将g包装成一个node天添加到全局的gcBgMarkWorkerPool中，保证标记协程与P的一对一关联，并调用 gopark 方法将当前 g 挂起，等待被唤醒.  
```
func gcBgMarkWorker() {
    gp := getg()
    node := new(gcBgMarkWorkerNode)
    gp.m.preemptoff = ""
    node.gp.set(gp)
    node.m.set(acquirem())
    // 唤醒外部的 for 循环
    notewakeup(&work.bgMarkReady)
    
    for {
        // 当前 g 阻塞至此，直到 gcController.findRunnableGCWorker 方法被调用，会将当前 g 唤醒
        gopark(func(g *g, nodep unsafe.Pointer) bool {
            node := (*gcBgMarkWorkerNode)(nodep)
            // ...
            // 将当前 g 包装成一个 node 添加到 gcBgMarkWorkerPool 中
            gcBgMarkWorkerPool.push(&node.node)          
            return true
        }, unsafe.Pointer(node), waitReasonGCWorkerIdle, traceEvGoBlock, 0)
        // ...
    }
}
```  
  
   
## 3.3 Stop the world  
  
gcStart 方法在调用gcBgMarkStartWorkers方法异步启动标记协程后，会执行STW操作停止所有用户协程，其实现位于 stopTheWorldWithSema 方法，核心点如下：  
- • 取锁：sched.lock  
  
- • 将 sched.gcwaiting 标识置为 1，后续的调度流程见其标识，都会阻塞挂起  
  
- • 抢占所有g，并将 P 的状态置为 syscall  
  
- • 将所有P的状态改为 stop  
  
- • 倘若部分任务无法抢占，则等待其完成后再进行抢占  
  
- • 调用方法worldStopped收尾，世界停止了  
  
```
func stopTheWorldWithSema() {
    _g_ := getg()


    // 全局调度锁
    lock(&sched.lock)
    sched.stopwait = gomaxprocs
    // 此标识置 1，之后所有的调度都会阻塞等待
    atomic.Store(&sched.gcwaiting, 1)
    // 发送抢占信息抢占所有 G，后将 p 状态置为 syscall
    preemptall()
    // 将当前 p 的状态置为 stop
    _g_.m.p.ptr().status = _Pgcstop // Pgcstop is only diagnostic.
    sched.stopwait--
    // 把所有 p 的状态置为 stop
    for _, p := range allp {
        s := p.status
        if s == _Psyscall && atomic.Cas(&p.status, s, _Pgcstop) {
            // ...
            p.syscalltick++
            sched.stopwait--
        }
    }
    // 把空闲 p 的状态置为 stop
    now := nanotime()
    for {
        p, _ := pidleget(now)
        if p == nil {
            break
        }
        p.status = _Pgcstop
        sched.stopwait--
    }
    wait := sched.stopwait > 0
    unlock(&sched.lock)




    // 倘若有 p 无法被抢占，则阻塞直到将其统统抢占完成
    if wait {
        for {
            // wait for 100us, then try to re-preempt in case of any races
            if notetsleep(&sched.stopnote, 100*1000) {
                noteclear(&sched.stopnote)
                break
            }
            preemptall()
        }
    }


    // native 方法，stop the world
    worldStopped()
}
```  
  
   
## 3.4 控制标记协程频率  
  
gcStart方法中，还会通过gcController.startCycle方法，将标记协程对CPU的占用率控制在 25% 左右. 此时，根据P的数量是否能被4整除，分为两种处理方式：  
- • 倘若P的个数能被4整除，则简单将标记协程的数量设置为P/4  
  
- • 倘若P的个数不能被4整除，则通过控制标记协程执行时长的方式，来使全局标记协程对CPU的使用率趋近于25%  
  
```
// 目标：标记协程对CPU的使用率维持在25%的水平
const gcBackgroundUtilization = 0.25


func (c *gcControllerState) startCycle(markStartTime int64, procs int, trigger gcTrigger) {
    // ...
    // P 的个数 * 0.25
    totalUtilizationGoal := float64(procs) * gcBackgroundUtilization
    // P 的个数 * 0.25 后四舍五入取整
    c.dedicatedMarkWorkersNeeded = int64(totalUtilizationGoal + 0.5)
    utilError := float64(c.dedicatedMarkWorkersNeeded)/totalUtilizationGoal - 1
    const maxUtilError = 0.3
    // 倘若 P 的个数不能被 4 整除
    if utilError < -maxUtilError || utilError > maxUtilError {        
        if float64(c.dedicatedMarkWorkersNeeded) > totalUtilizationGoal {    
            c.dedicatedMarkWorkersNeeded--
        }
        // 计算出每个 P 需要额外执行标记任务的时间片比例
        c.fractionalUtilizationGoal = (totalUtilizationGoal - float64(c.dedicatedMarkWorkersNeeded)) / float64(procs)
    // 倘若 P 的个数可以被 4 整除，则无需控制执行时长
    } else {
        c.fractionalUtilizationGoal = 0
    }
    // ...
}
```  
  
   
## 3.5 设置写屏障  
  
随后，gcStart方法会调用setGCPhase方法，标志GC正式进入并发标记（GCmark）阶段. 我们观察该方法代码实现，可以注意到，在_GCMark和_GCMarkTermination阶段中，会启用混合写屏障.  
```
func setGCPhase(x uint32) {
    atomic.Store(&gcphase, x)
    writeBarrier.needed = gcphase == _GCmark || gcphase == _GCmarktermination
    writeBarrier.enabled = writeBarrier.needed || writeBarrier.cgo
}
```  
  
   
  
在混合写屏障机制中，核心是会将需要置灰的对象添加到当前P的wbBuf缓存中. 随后在并发标记缺灰、标记终止前置检查等时机会执行wbBufFlush1方法，批量地将wbBuf中的对象释放出来进行置灰，保证达到预期的效果.  
```
func wbBufFlush(dst *uintptr, src uintptr) {
    // ...
    systemstack(func() {
        wbBufFlush1(getg().m.p.ptr())
    })
}
```  
  
wbBufFlush1方法中涉及了对象置灰操作，其包含了在对应mspan的bitmap中打点标记以及将对象添加到gcw队列两步.此处先不细究，后文4.3小节中，我们再作详细介绍.  
```
func wbBufFlush1(_p_ *p) {
    // 获取当前 P 通过屏障机制缓存的指针
    start := uintptr(unsafe.Pointer(&_p_.wbBuf.buf[0]))
    n := (_p_.wbBuf.next - start) / unsafe.Sizeof(_p_.wbBuf.buf[0])
    ptrs := _p_.wbBuf.buf[:n]


    // 将缓存的指针作标记，添加到 gcw 队列
    gcw := &_p_.gcw
    pos := 0
    for _, ptr := range ptrs {
        // ...
        obj, span, objIndex := findObject(ptr, 0, 0)
        if obj == 0 {
            continue
        }
        // 打标
        mbits := span.markBitsForIndex(objIndex)
        if mbits.isMarked() {
            continue
        }
        mbits.setMarked()
        // ...
    }


    // 所有缓存对象入队
    gcw.putBatch(ptrs[:pos])
    _p_.wbBuf.reset()
}
```  
  
   
## 3.6 Tiny 对象标记  
  
gcStart方法随后还会调用gcMarkTinyAllocs方法中，遍历所有的P，对mcache中的Tiny对象分别调用greyobject方法进行置灰.  
```
func gcMarkTinyAllocs() {
    assertWorldStopped()


    for _, p := range allp {
        c := p.mcache
        if c == nil || c.tiny == 0 {
            continue
        }
        // 获取 tiny 对象
        _, span, objIndex := findObject(c.tiny, 0, 0)
        gcw := &p.gcw
        // tiny 对象置灰(标记 + 添加入队)
        greyobject(c.tiny, 0, 0, span, gcw, objIndex)
    }
}
```  
  
   
## 3.7 Start the world  
  
startTheWorldWithSema与stopTheWorldWithSema形成对偶. 该方法会重新恢复世界的生机，将所有P唤醒. 倘若缺少M，则构造新的M为P补齐（M和P是Golang GMP 模型中的概念，可参见我的文章Golang GMP 原理）.  
```
func startTheWorldWithSema(emitTraceEvent bool) int64 {
    assertWorldStopped()
   
    // ...   
    p1 := procresize(procs)
    // 重启世界
    worldStarted()


    // 遍历所有 p，将其唤醒
    for p1 != nil {
        p := p1
        p1 = p1.link.ptr()
        if p.m != 0 {
            mp := p.m.ptr()
            p.m = 0
            if mp.nextp != 0 {
                throw("startTheWorld: inconsistent mp->nextp")
            }
            mp.nextp.set(p)
            notewakeup(&mp.park)
        } else {           
            newm(nil, p, -1)
        }
    }


    // ...
    return startTime
}
```  
  
   
# 4 并发标记  
  
![](https://mmbiz.qpic.cn/mmbiz_png/3ic3aBqT2ibZu8WccNVUMwlnMQBKA4T5pPDf2VicPzeBEyoAqiceh8al9iaVNcTibMavM1GYxogFWFjScVkQ5oBwYuog/640?wx_fmt=png "")  
  
   
  
下面比如难度曲线最陡峭的并发标记部分. 这部分内容承接上文3.2小节，讲述标记协程在被唤醒后，需要执行的任务细节.  
  
首先，我们先来理一下，这些标记协程是如何被唤醒的.  
## 4.1 调度标记协程  
  
<table><thead style="line-height: 1.75;background: rgba(0, 0, 0, 0.05);font-weight: bold;color: rgb(63, 63, 63);"><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;"><strong style="line-height: 1.75;color: rgb(15, 76, 129);">方法</strong></td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;"><strong style="line-height: 1.75;color: rgb(15, 76, 129);">文件</strong></td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;"><strong style="line-height: 1.75;color: rgb(15, 76, 129);">作用</strong></td></tr></thead><tbody><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">schedule</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime/proc.go</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">调度协程</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">findRunnable</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime/proc.go</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">获取可执行的协程</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">gcControllerState.findRunnableGCWorker</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime/mgcspacer.go</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">获取可执行的标记协程，同时将该协程唤醒</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">execute</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime/proc.go</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">执行协程</td></tr></tbody></table>  
  
在GMP调度的主干方法schedule中，会通过g0调用findRunnable方法P寻找下一个可执行的协程，找到后会调用execute方法，内部完成由g0->g的切换，真正执行用户协程中的任务.  
```
func schedule() {
    // ...
    gp, inheritTime, tryWakeP := findRunnable()
    // ...
    execute(gp, inheritTime)
}
```  
  
   
  
在findRunnable方法中，当通过全局标识gcBlackenEnabled发现当前开启GC模式时，会调用 gcControllerState.findRunnableGCWorker唤醒并取得标记协程.  
```
func findRunnable() (gp *g, inheritTime, tryWakeP bool) {
    // ...
    if gcBlackenEnabled != 0 {
        gp, now = gcController.findRunnableGCWorker(_p_, now)
        if gp != nil {
            return gp, false, true
        }
    }
    // ...
}
```  
  
   
  
在gcControllerState.findRunnableGCWorker方法中，会从全局的标记协程池 gcBgMarkWorkerPool获取到一个封装了标记协程的node. 并通过gcControllerState中 dedicatedMarkWorkersNeeded、fractionalUtilizationGoal等字段标识判定标记协程的标记模式，然后将标记协程状态由_Gwaiting唤醒为_Grunnable，并返回给 g0 用于执行.  
  
这里谈到的标记模式对应了上文3.4小节的内容，并将在下文4.2小节详细介绍.  
```
func (c *gcControllerState) findRunnableGCWorker(_p_ *p, now int64) (*g, int64) {
    // ...
    // 保证当前 _p_ 是可以调度标记协程的，每个 p 只能执行一个标记协程
    if !gcMarkWorkAvailable(_p_) {
        return nil, now
    }


    // 从全局标记协程池子 gcBgMarkWorkerPool 中取出 g
    node := (*gcBgMarkWorkerNode)(gcBgMarkWorkerPool.pop())
    // ...


    decIfPositive := func(ptr *int64) bool {
        for {
            v := atomic.Loadint64(ptr)
            if v <= 0 {
                return false
            }


            if atomic.Casint64(ptr, v, v-1) {
                return true
            }
        }
    }


    // 确认标记的模式
    if decIfPositive(&c.dedicatedMarkWorkersNeeded) {      
        _p_.gcMarkWorkerMode = gcMarkWorkerDedicatedMode
    } else if c.fractionalUtilizationGoal == 0 {
                gcBgMarkWorkerPool.push(&node.node)
        return nil, now
    } else {
        delta := now - c.markStartTime
        if delta > 0 && float64(_p_.gcFractionalMarkTime)/float64(delta) > c.fractionalUtilizationGoal {
            // Nope. No need to run a fractional worker.
            gcBgMarkWorkerPool.push(&node.node)
            return nil, now
        }
        // Run a fractional worker.
        _p_.gcMarkWorkerMode = gcMarkWorkerFractionalMode
    }


   // 将标记协程的状态置为 runnable，填了 gcBgMarkWorker 方法中 gopark 操作留下的坑
    gp := node.gp.ptr()
    casgstatus(gp, _Gwaiting, _Grunnable)
    return gp, n
}
```  
  
   
  
   
## 4.2 并发标记启动  
  
<table><thead style="line-height: 1.75;background: rgba(0, 0, 0, 0.05);font-weight: bold;color: rgb(63, 63, 63);"><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;"><strong style="line-height: 1.75;color: rgb(15, 76, 129);">方法</strong></td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;"><strong style="line-height: 1.75;color: rgb(15, 76, 129);">文件</strong></td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;"><strong style="line-height: 1.75;color: rgb(15, 76, 129);">作用</strong></td></tr></thead><tbody><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">gcBgMarkWorker</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime/mgc.go</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">标记协程主方法</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">gcDrain</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime/mgcmark.go</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">循环处理gcw队列主方法</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">markroot</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime/mgcmark.go</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">标记根对象</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">scanobject</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime/mgcmark.go</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">扫描一个对象，将其指向对象分别置灰</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">greyobject</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime/mgcmark.go</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">将一个对象置灰</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">markBits.setMarked</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime/mbitmap.go</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">标记一个对象</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">gcWork.putFast/put</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime/mgcwork.go</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">将一个对象加入gcw队列</td></tr></tbody></table>  
  
标记协程被唤醒后，主线又重新拉回到gcBgMarkWorker方法中，此时会根据3.4小节中预设的标记模式，调用gcDrain方法开始执行并发标记工作.  
  
标记模式包含以下三种：  
- • gcMarkWorkerDedicatedMode：专一模式. 需要完整执行完标记任务，不可被抢占  
  
- • gcMarkWorkerFractionalMode：分时模式. 当标记协程执行时长达到一定比例后，可以被抢占  
  
- • gcMarkWorkerIdleMode: 空闲模式. 随时可以被抢占.  
  
值得一提的是，在执行专一模式时，会先以可被抢占的模式尝试执行，倘若真的被用户协程抢占，则会先将当前P本地队列的用户协程投放到全局g队列中，再将标记模式改为不可抢占模式. 这样设计的优势是，通过负载均衡的方式，减少当前P下用户协程的等待时长，提高用户体验.  
  
在gcDrain方法中，有两个核心的gcDrainFlags控制着标记协程的运行风格：  
- • gcDrainIdle：空闲模式，随时可被抢占  
  
- • gcDrainFractional：分时模式，执行一定比例的时长后可被抢占  
  
   
```
type gcDrainFlags int
const (
    gcDrainUntilPreempt gcDrainFlags = 1 << iota
    gcDrainFlushBgCredit
    gcDrainIdle
    gcDrainFractional
)
func gcBgMarkWorker() {
        // ...


        node.m.set(acquirem())
        pp := gp.m.p.ptr() // P can't change with preemption disabled.


       // ...
        
       // 根据不同的运作模式，执行 gcDrain 方法：
        systemstack(func() {
          
            casgstatus(gp, _Grunning, _Gwaiting)
            switch pp.gcMarkWorkerMode {
            default:
                throw("gcBgMarkWorker: unexpected gcMarkWorkerMode")
            case gcMarkWorkerDedicatedMode:
               // 先按照可抢占模式执行标记协程，倘若被抢占，则将抢占协程添加到全局队列中，之后再以不可抢占模式执行标记协程
                gcDrain(&pp.gcw, gcDrainUntilPreempt|gcDrainFlushBgCredit)
                if gp.preempt {
                    // 将 p 本地队列中的 g 添加到全局队列
                    if drainQ, n := runqdrain(pp); n > 0 {
                        lock(&sched.lock)
                        globrunqputbatch(&drainQ, int32(n))
                        unlock(&sched.lock)
                    }
                }
                // Go back to draining, this time
                // without preemption.
                gcDrain(&pp.gcw, gcDrainFlushBgCredit)
            case gcMarkWorkerFractionalMode:
                gcDrain(&pp.gcw, gcDrainFractional|gcDrainUntilPreempt|gcDrainFlushBgCredit)
            case gcMarkWorkerIdleMode:
                gcDrain(&pp.gcw, gcDrainIdle|gcDrainUntilPreempt|gcDrainFlushBgCredit)
            }
            casgstatus(gp, _Gwaiting, _Grunning)
        })


        // ...
    }
}
```  
  
   
## 4.3 标记主流程  
  
gcDrain 方法是并发标记阶段的核心方法：  
- • 在空闲模式（idle）和分时模式（fractional）下，会提前设好 check 函数（pollWork 和 pollFractionalWorkerExit）  
  
- • 标记根对象  
  
- • 循环从gcw缓存队列中取出灰色对象，执行scanObject方法进行扫描标记  
  
- • 定期检查check 函数，判断标记流程是否应该被打断  
  
```
func gcDrain(gcw *gcWork, flags gcDrainFlags) {
    // ...
    
    gp := getg().m.curg
    // 模式标记
    preemptible := flags&gcDrainUntilPreempt != 0
    flushBgCredit := flags&gcDrainFlushBgCredit != 0
    idle := flags&gcDrainIdle != 0


    // ...
    var check func() bool
    if flags&(gcDrainIdle|gcDrainFractional) != 0 {
        // ...
        if idle {
            check = pollWork
        } else if flags&gcDrainFractional != 0 {
            check = pollFractionalWorkerExit
        }
    }


    // 倘若根对象还未标记完成，则先进行根对象标记
    if work.markrootNext < work.markrootJobs {
        // Stop if we're preemptible or if someone wants to STW.
        for !(gp.preempt && (preemptible || atomic.Load(&sched.gcwaiting) != 0)) {
            job := atomic.Xadd(&work.markrootNext, +1) - 1
            if job >= work.markrootJobs {
                break
            }
            // 标记根对象
            markroot(gcw, job, flushBgCredit)
            // ...
        }
    }


    // 遍历队列，进行对象标记
    for !(gp.preempt && (preemptible || atomic.Load(&sched.gcwaiting) != 0)) {
        // work balance
        if work.full == 0 {
            gcw.balance()
        }


        // 尝试从 p 本地队列中获取灰色对象，无锁
        b := gcw.tryGetFast()
        if b == 0 {
            // 尝试从全局队列中获取灰色对象，加锁
            b = gcw.tryGet()
            if b == 0 {
                // 刷新写屏障缓存
                wbBufFlush(nil, 0)
                b = gcw.tryGet()
            }
        }
        if b == 0 {
            // 已无对象需要标记
            break
        }
        // 进行对象的标记，并顺延指针进行后续对象的扫描
        scanobject(b, gcw)


        // ...
        
        if gcw.heapScanWork >= gcCreditSlack {
            gcController.heapScanWork.Add(gcw.heapScanWork)
            // ...
            if checkWork <= 0 {
                // ...
                if check != nil && check() {
                    break
                }
            }
        }
    }


done:
    // 
}
```  
  
   
## 4.4 灰对象缓存队列  
  
4.3小节的源码中，涉及到一个重要的数据结构：gcw，这是灰色对象的存储代理和载体，在标记过程中需要持续不断地从从队列中取出灰色对象，进行扫描，并将新的灰色对象通过gcw添加到缓存队列.  
  
灰对象缓存队列分为两层：  
- • 每个P私有的gcWork，实现上由两条单向链表构成，采用轮换机制使用  
  
- • 全局队列workType.full，底层是一个通过CAS操作维护的栈结构，由所有P共享  
  
   
  
（1）gcWork  
  
gcWork数据结构源代码如下所示.  
```
type gcWork struct {
    // ...
    wbuf1, wbuf2 *workbuf
    // ...
}


type workbuf struct {
    workbufhdr
    obj [(_WorkbufSize - unsafe.Sizeof(workbufhdr{})) / goarch.PtrSize]uintptr
}




type workbufhdr struct {
    node lfnode 
    nobj int
}




type lfnode struct {
    next    uint64
    pushcnt uint
}
```  
  
在gcDrain方法中，会持续不断地从当前P的gcw中获取灰色对象，在调用策略上，会先尝试取私有部分，再通过gcw代理取全局共享部分：  
```
        // 尝试从 p 本地队列中获取灰色对象，无锁
        b := gcw.tryGetFast()
        if b == 0 {
            // 尝试从全局队列中获取灰色对象，加锁
            b = gcw.tryGet()
            if b == 0 {
                // 因为缺灰，会释放写屏障缓存，进行补灰操作
                wbBufFlush(nil, 0)
                b = gcw.tryGet()
            }
       }
```  
  
   
  
gcWork.tryGetFast方法中，会先尝试从gcWork.wbuf1 中获取灰色对象.  
```
func (w *gcWork) tryGetFast() uintptr {
    wbuf := w.wbuf1
    if wbuf == nil || wbuf.nobj == 0 {
        return 0
    }


    wbuf.nobj--
    return wbuf.obj[wbuf.nobj]
}
```  
  
   
  
倘若gcWork.wbuf1缺灰，则会在gcWork.tryGet方法中交换wbuf1和wbuf2，再尝试获取一次. 倘若仍然缺灰，则会调用 trygetfull 方法，从全局缓存队列中获取.  
```
func (w *gcWork) tryGet() uintptr {
    wbuf := w.wbuf1
    if wbuf == nil {
        w.init()
        wbuf = w.wbuf1
        // wbuf is empty at this point.
    }
    if wbuf.nobj == 0 {
        w.wbuf1, w.wbuf2 = w.wbuf2, w.wbuf1
        wbuf = w.wbuf1
        if wbuf.nobj == 0 {
            owbuf := wbuf
            wbuf = trygetfull()
            if wbuf == nil {
                return 0
            }
            putempty(owbuf)
            w.wbuf1 = wbuf
        }
    }


    wbuf.nobj--
    return wbuf.obj[wbuf.nobj]
}
```  
  
   
  
   
  
（2）workType.full  
  
灰色对象的全局缓存队列是一个栈结构，调用pop方法时，会通过CAS方式依次从栈顶取出一个缓存链表.  
```
var work workType
type workType struct {
    full lfstack
    // ...
}
```  
  
   
```
type lfstack uint64


func (head *lfstack) push(node *lfnode) {
    // ...
}


func (head *lfstack) pop() unsafe.Pointer {
    for {
        old := atomic.Load64((*uint64)(head))
        if old == 0 {
            return nil
        }
        node := lfstackUnpack(old)
        next := atomic.Load64(&node.next)
        if atomic.Cas64((*uint64)(head), old, next) {
            return unsafe.Pointer(node)
        }
    }
}
```  
  
   
```
func trygetfull() *workbuf {
    b := (*workbuf)(work.full.pop())
    if b != nil {
        b.checknonempty()
        return b
    }
    return b
}
```  
  
   
## 4.5 三色标记实现  
  
![](https://mmbiz.qpic.cn/mmbiz_png/3ic3aBqT2ibZu8WccNVUMwlnMQBKA4T5pPW0icniceY5Pmyh5PP1Ow7WAvpaV34oIdBnfftCKflMPINdl69HZbowKQ/640?wx_fmt=png "")  
  
   
  
Golang GC的标记流程基于三色标记法实现. 此时在将理论落地实践前，我们需要先搞清楚一个细节，那就是在代码层面，黑、灰、白这三种颜色如何实现.  
  
在前文 Golang内存模型与分配机制中聊过，每个对象会有其从属的mspan，在mspan中，有着两个bitmap存储着每个对象大小的内存的状态信息：  
- • allocBits：标识内存的闲忙状态，一个bit位对应一个object大小的内存块，值为1代表已使用；值为0代表未使用  
  
- • gcmakrBits：只在GC期间使用. 值为1代表占用该内存块的对象被标记存活.  
  
在垃圾清扫的过程中，并不会真正地将内存进行回收，而是在每个mspan中使用gcmakrBits对allocBits进行覆盖. 在分配新对象时，当感知到mspan的allocBits中，某个对象槽位bit位值为0，则会将其视为空闲内存进行使用，其本质上可能是一个覆盖操作.  
  
   
```
type mspan struct {
    // ...
    allocBits  *gcBits
    gcmarkBits *gcBits
    // ...
}


type gcBits uint8
```  
  
   
  
介绍完了bitmap设定之后，下面回到三种标记色的实现当中：  
- • 黑色：对象在mspan.gcmarkBits中bit位值为1，且对象已经离开灰对象缓存队列（4.4小节谈及）  
  
- • 灰色：对象在mspan.gcmarkBits中bit位值为1，且对象仍处于灰对象缓存队列中  
  
- • 白色：对象在mspan.gcmarkBits中bit位值位0.  
  
   
  
有了以上的基础设定之后，我们已经可以在脑海中搭建三色标记法的实现框架：  
- • 扫描根对象，将gcmarkBits中的bit位置1，并添加到灰对象缓存队列  
  
- • 依次从灰对象缓存队列中取出灰对象，将其指向对象的gcmarkBits 中的bit位置1并添加到会对象缓存队列  
  
   
## 4.6 中止标记协程  
  
gcDrain方法中，针对空闲模式idle和分时模式fractional，会设定check函数，在循环扫描的过程中检测是否需要中断当前标记协程.  
```
func gcDrain(gcw *gcWork, flags gcDrainFlags) {
    // ...
    // ...
    idle := flags&gcDrainIdle != 0


    // ...
    var check func() bool
    if flags&(gcDrainIdle|gcDrainFractional) != 0 {
        // ...
        if idle {
            check = pollWork
        } else if flags&gcDrainFractional != 0 {
            check = pollFractionalWorkerExit
        }
    }
    // ...
    // 遍历队列，进行对象标记
    for !(gp.preempt && (preemptible || atomic.Load(&sched.gcwaiting) != 0)) {
        // ...   
        if gcw.heapScanWork >= gcCreditSlack {
            gcController.heapScanWork.Add(gcw.heapScanWork)
            // ...
            if checkWork <= 0 {
                // ...
                if check != nil && check() {
                    break
                }
            }
        }
    }




done:
    //
}
```  
  
   
  
对应于idle模式的check函数是pollwork，方法中判断P本地队列存在就绪的g或者存在就绪的网络写成，就会对当前标记协程进行中断：  
```
func pollWork() bool {
    if sched.runqsize != 0 {
        return true
    }
    p := getg().m.p.ptr()
    if !runqempty(p) {
        return true
    }
    if netpollinited() && atomic.Load(&netpollWaiters) > 0 && sched.lastpoll != 0 {
        if list := netpoll(0); !list.empty() {
            injectglist(&list)
            return true
        }
    }
    return false
}
```  
  
   
  
对应于 fractional 模式的check函数是pollFractionalWorkerExit，倘若当前标记协程执行的时间比例大于 1.2 倍的 fractionalUtilizationGoal 阈值（3.4小节中设置），就会中止标记协程.  
```
func pollFractionalWorkerExit() bool {
    
    now := nanotime()
    delta := now - gcController.markStartTime
    if delta <= 0 {
        return true
    }
    p := getg().m.p.ptr()
    selfTime := p.gcFractionalMarkTime + (now - p.gcMarkWorkerStartTime)
   
    return float64(selfTime)/float64(delta) > 1.2*gcController.fractionalUtilizationGoal
}
```  
## 4.7 扫描根对象  
  
在gcDrain方法正式开始循环扫描前，还会先对根对象进行扫描标记. Golang中的根对象包括如下几项：  
- • .bss段内存中的未初始化全局变量  
  
- • .data段内存中的已初始化变量）  
  
- • span 中的 finalizer  
  
- • 各协程栈  
  
   
  
实现根对象扫描的方法是markroot：  
```
func markroot(gcw *gcWork, i uint32, flushBgCredit bool) int64 {
    var workDone int64
    var workCounter *atomic.Int64
    switch {
    // 处理已初始化的全局变量
    case work.baseData <= i && i < work.baseBSS:
        workCounter = &gcController.globalsScanWork
        for _, datap := range activeModules() {
            workDone += markrootBlock(datap.data, datap.edata-datap.data, datap.gcdatamask.bytedata, gcw, int(i-work.baseData))
        }
    // 处理未初始化的全局变量
    case work.baseBSS <= i && i < work.baseSpans:
        workCounter = &gcController.globalsScanWork
        for _, datap := range activeModules() {
            workDone += markrootBlock(datap.bss, datap.ebss-datap.bss, datap.gcbssmask.bytedata, gcw, int(i-work.baseBSS))
        }
    // 处理 finalizer 队列
    case i == fixedRootFinalizers:
        for fb := allfin; fb != nil; fb = fb.alllink {
            cnt := uintptr(atomic.Load(&fb.cnt))
            scanblock(uintptr(unsafe.Pointer(&fb.fin[0])), cnt*unsafe.Sizeof(fb.fin[0]), &finptrmask[0], gcw, nil)
        }
    //  释放已终止的 g 的栈
    case i == fixedRootFreeGStacks:
        systemstack(markrootFreeGStacks)
    // 扫描 mspan 中的 special
    case work.baseSpans <= i && i < work.baseStacks:
        markrootSpans(gcw, int(i-work.baseSpans))


    default:
        // ...
        // 获取需要扫描的 g
        gp := work.stackRoots[i-work.baseStacks]
        // ...
        // 切回到 g0执行工作，扫描 g 的栈
        systemstack(func() {
            // ...
            // 栈扫描
            workDone += scanstack(gp, gcw)
           // ...
        })
    }
    // ...
    return workDone
}
```  
  
   
  
其中，栈扫描方法链路展开如下：  
```
func scanstack(gp *g, gcw *gcWork) int64 {
    // ...


    scanframe := func(frame *stkframe, unused unsafe.Pointer) bool {
        scanframeworker(frame, &state, gcw)
        return true
    }
    gentraceback(^uintptr(0), ^uintptr(0), 0, gp, 0, nil, 0x7fffffff, scanframe, nil, 0)
   // ...
}
```  
  
   
```
func scanframeworker(frame *stkframe, state *stackScanState, gcw *gcWork) {
    // ...
    // 扫描局部变量
    if locals.n > 0 {
        size := uintptr(locals.n) * goarch.PtrSize
        scanblock(frame.varp-size, size, locals.bytedata, gcw, state)
    }


    // 扫描函数参数
    if args.n > 0 {
        scanblock(frame.argp, uintptr(args.n)*goarch.PtrSize, args.bytedata, gcw, state)
    }
    // ...
}
```  
  
   
  
不论是全局变量扫描还是栈变量扫描，底层都会调用到scanblock方法. 在扫描时，会通过位图ptrmask辅助加速流程. 在 ptrmask当中，每个bit位对应了一个指针大小（8B）的位置的标识信息，指明当前位置是否是指针，倘若非指针，则直接跳过扫描.  
  
此外,在标记一个对象时,需要获取到该对象所在mspan,这一过程会使用到heapArena中关于页和mspan间的映射索引（如有存疑可以看我的文章 Golang内存模型与分配机制），这部分内容放在 4.7 小节中集中阐述.  
```
func scanblock(b0, n0 uintptr, ptrmask *uint8, gcw *gcWork, stk *stackScanState) {
  // ...
  b := b0
  n := n0
  // 遍历待扫描的地址
  for i := uintptr(0); i < n; {
  // 找到 bitmap 对应的 byte. ptrmask 辅助标识了 .data 一个指针的大小，bit 位为 1 代表当前位置是一个指针
  bits := uint32(*addb(ptrmask, i/(goarch.PtrSize*8)))
       // 非指针，跳过
   if bits == 0 {
        i += goarch.PtrSize * 8
        continue
    }
    for j := 0; j < 8 && i < n; j++ {
      if bits&1 != 0 {
      // Same work as in scanobject; see comments there.
        p := *(*uintptr)(unsafe.Pointer(b + i))
        if p != 0 {
          if obj, span, objIndex := findObject(p, b, i); obj != 0 {
            greyobject(obj, b, i, span, gcw, objIndex)
          } else if stk != nil && p >= stk.stack.lo && p < stk.stack.hi {
           stk.putPtr(p, false)
          }
        }
      }
      bits >>= 1
      i += goarch.PtrSize
    }
  }
 }
```  
## 4.7 扫描普通对象  
  
gcDrain 方法中，会持续从灰对象缓存队列中取出灰对象，然后采用scanobject 方法进行处理.  
```
func gcDrain(gcw *gcWork, flags gcDrainFlags) {
    // ...
    // 遍历队列，进行对象标记
    for !(gp.preempt && (preemptible || atomic.Load(&sched.gcwaiting) != 0)) {
       
        // 尝试从 p 本地队列中获取灰色对象，无锁
        b := gcw.tryGetFast()
        if b == 0 {
            // 尝试从全局队列中获取灰色对象，加锁
            b = gcw.tryGet()
            if b == 0 {
                // 刷新写屏障缓存
                wbBufFlush(nil, 0)
                b = gcw.tryGet()
            }
        }
        if b == 0 {
            // 已无对象需要标记
            break
        }
        // 进行对象的标记，并顺延指针进行后续对象的扫描
        scanobject(b, gcw)


    }




done:
    //
}
```  
  
   
  
scanobject方法遍历当前灰对象中的指针，依次调用greyobject方法将其指向的对象进行置灰操作.  
```
const (
    bitPointer = 1 << 0
    bitScan    = 1 << 4
)


func scanobject(b uintptr, gcw *gcWork) {
    // 通过地址映射到所属的页
    // 通过 heapArena 中的映射信息，从页映射到所属的 mspan
    hbits := heapBitsForAddr(b)
    s := spanOfUnchecked(b)
    n := s.elemsize
    // ...


    // 顺延当前对象的成员指针，扫描后续的对象
    var i uintptr
    for i = 0; i < n; i, hbits = i+goarch.PtrSize, hbits.next() {
        // 通过 heapArena 中的 bitmap 记录的信息，加速遍历过程
        bits := hbits.bits()
        if bits&bitScan == 0 {
            break // no more pointers in this object
        }
        if bits&bitPointer == 0 {
            continue // not a pointer
        }


        obj := *(*uintptr)(unsafe.Pointer(b + i))
      
        if obj != 0 && obj-b >= n {
            // 对于遍历到的对象，将其置灰，并添加到队列中，等待后续扫描
            if obj, span, objIndex := findObject(obj, b, i); obj != 0 {
                greyobject(obj, b, i, span, gcw, objIndex)
            }
        }
    }
    // ...
}
```  
  
在scanobject方法中还涉及到两项细节：  
  
（1）如何通过对象地址找到其所属的mspan  
  
首先根据对象地址，可以定位到对象所属的页，进一步可以通过地址偏移定位到其所属的heapArena. 在heapArena中，已经提前建立好了从页映射到mspan的索引，于是我们通过这一链路，实现从对象地址到mspan的映射. 从而能够获得mspan.gcmarkBits进行bitmap标记操作.  
```
type heapArena struct {
    spans [pagesPerArena]*mspan
}
```  
  
   
```
func findObject(p, refBase, refOff uintptr) (base uintptr, s *mspan, objIndex uintptr) {
    s = spanOf(p)
    // ...
    return
}


func spanOf(p uintptr) *mspan {
    // ...
    ri := arenaIndex(p)
    // ...
    l2 := mheap_.arenas[ri.l1()]
    // ...
    ha := l2[ri.l2()]
    // ...
    return ha.spans[(p/pageSize)%pagesPerArena]
}
```  
  
   
  
   
  
（2）如何加速扫描过程  
  
![](https://mmbiz.qpic.cn/mmbiz_png/3ic3aBqT2ibZu8WccNVUMwlnMQBKA4T5pPDp4elxgYCia1enDpHhUyoaia9Q55icqoxYNUaPSCPkI7pTzkV0F8sUbVQ/640?wx_fmt=png "")  
  
在heapArena中，通过一个额外的bitmap存储了内存信息：  
  
bitmap中，每两个bit记录一个指针大小的内存空间的信息（8B），其中一个bit标志了该位置是否是指针；另一个bit标志了该位置往后是否还存在指针，于是在遍历扫描的过程中，可以通过这两部分信息推进for循环的展开速度.  
```
const heapArenaBitmapBytes untyped int = 2097152


type heapArena struct {
    bitmap [heapArenaBitmapBytes]byte
    // ...
}
```  
  
   
  
   
```
func heapBitsForAddr(addr uintptr) (h heapBits) {
    // 2 bits per word, 4 pairs per byte, and a mask is hard coded.
    arena := arenaIndex(addr)
    ha := mheap_.arenas[arena.l1()][arena.l2()]
    if ha == nil {
        return
    }
    h.bitp = &ha.bitmap[(addr/(goarch.PtrSize*4))%heapArenaBitmapBytes]
    h.shift = uint32((addr / goarch.PtrSize) & 3)
    h.arena = uint32(arena)
    h.last = &ha.bitmap[len(ha.bitmap)-1]
    return
}
```  
  
   
```
func (h heapBits) bits() uint32 {
    // The (shift & 31) eliminates a test and conditional branch
    // from the generated code.
    return uint32(*h.bitp) >> (h.shift & 31)
}
```  
  
   
## 4.8 对象置灰  
  
对象置灰操作位于greyobject方法中. 如4.5小节所属，置灰分两步：  
- • 将mspan.gcmarkBits对应bit位置为1  
  
- • 将对象添加到灰色对象缓存队列  
  
```
func greyobject(obj, base, off uintptr, span *mspan, gcw *gcWork, objIndex uintptr) {
    // ...
    // 在其所属的 mspan 中，将对应位置的 gcMark bitmap 位置为 1
    mbits.setMarked()
    
    // ...
    // 将对象添加到当前 p 的本地队列
    if !gcw.putFast(obj) {
        gcw.put(obj)
    }
}
```  
  
   
## 4.9 新分配对象置黑  
  
此外，值得一提的是，GC期间新分配的对象，会被直接置黑，呼应了混合写屏障中的设定.  
```
func mallocgc(size uintptr, typ *_type, needzero bool) unsafe.Pointer {
        // ...
        if gcphase != _GCoff {
            gcmarknewobject(span, uintptr(x), size, scanSize)
        }
        // ...
}
```  
  
   
```
func gcmarknewobject(span *mspan, obj, size, scanSize uintptr) {
    // ...
    objIndex := span.objIndex(obj)
    // 标记对象
    span.markBitsForIndex(objIndex).setMarked()
    // ...
}
```  
  
   
# 5 辅助标记  
## 5.1 辅助标记策略  
  
在并发标记阶段，由于用户协程与标记协程共同工作，因此在极端场景下可能存在一个问题——倘若用户协程分配对象的速度快于标记协程标记对象的速度，这样标记阶段岂不是永远无法结束？  
  
为规避这一问题，Golang GC引入了辅助标记的策略，建立了一个兜底的机制：在最坏情况下，一个用户协程分配了多少内存，就需要完成对应量的标记任务.  
  
在每个用户协程 g 中，有一个字段 gcAssisBytes，象征GC期间可分配内存资产的概念，每个 g 在GC期间辅助标记了多大的内存空间，就会获得对应大小的资产，使得其在GC期间能多分配对应大小的内存进行对象创建.  
  
   
```
type g struct {
    // ...
    gcAssistBytes int64
}
```  
  
   
```
func mallocgc(size uintptr, typ *_type, needzero bool) unsafe.Pointer {
    // ...
    var assistG *g
    if gcBlackenEnabled != 0 {       
        assistG = getg()
        if assistG.m.curg != nil {
            assistG = assistG.m.curg
        }
        // 每个 g 会有资产
        assistG.gcAssistBytes -= int64(size)


        if assistG.gcAssistBytes < 0 {           
            gcAssistAlloc(assistG)
        }
    }
}
```  
  
   
## 5.2 辅助标记执行  
  
由于各对象中，可能存在部分不包含指针的字段，这部分字段是无需进行扫描的. 因此真正需要扫描的内存量会小于实际的内存大小，两者之间的比例通过gcController.assistWorkPerByte进行记录.  
  
于是当一个用户协程在GC期间需要分配M大小的新对象时，实际上需要完成的辅助标记量应该为assistWorkPerByte*M.  
  
辅助标记逻辑位于gcAssistAlloc方法. 在该方法中，会先尝试从公共资产池gcController.bgScanCredit中偷取资产，倘若资产仍然不够，则会通过systemstack方法切换至g0，并在 gcAssistAlloc1 方法内调用 gcDrainN 方法参与到并发标记流程当中.  
```
func gcAssistAlloc(gp *g) {
    // ...
    // 计算待完成的任务量
    debtBytes := -gp.gcAssistBytes
    assistWorkPerByte := gcController.assistWorkPerByte.Load()
    scanWork := int64(assistWorkPerByte * float64(debtBytes))
    if scanWork < gcOverAssistWork {
        scanWork = gcOverAssistWork
        debtBytes = int64(assistBytesPerWork * float64(scanWork))
    }


    // 先尝试从全局的可用资产中偷取
    bgScanCredit := atomic.Loadint64(&gcController.bgScanCredit)
    stolen := int64(0)
    if bgScanCredit > 0 {
        if bgScanCredit < scanWork {
            stolen = bgScanCredit
            gp.gcAssistBytes += 1 + int64(assistBytesPerWork*float64(stolen))
        } else {
            stolen = scanWork
            gp.gcAssistBytes += debtBytes
        }
        atomic.Xaddint64(&gcController.bgScanCredit, -stolen)
        scanWork -= stolen
        // 全局资产够用，则无需辅助标记，直接返回
        if scanWork == 0 {         
            return
        }
    }


    // 切换到 g0，开始执行标记任务
    systemstack(func() {
        gcAssistAlloc1(gp, scanWork)        
    })


    // 辅助标记完成
    completed := gp.param != nil
    gp.param = nil
    if completed {
        gcMarkDone()
    }
    // ...
}
```  
#   
# 6 标记终止  
  
![](https://mmbiz.qpic.cn/mmbiz_png/3ic3aBqT2ibZu8WccNVUMwlnMQBKA4T5pPvhtP0Mfg1ZNdCItp8MUycSGib9CJ1dJosjH9SQZvJ73Nibib0R8p3oY1Q/640?wx_fmt=png "")  
  
   
  
<table><thead style="line-height: 1.75;background: rgba(0, 0, 0, 0.05);font-weight: bold;color: rgb(63, 63, 63);"><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;"><strong style="line-height: 1.75;color: rgb(15, 76, 129);">方法</strong></td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;"><strong style="line-height: 1.75;color: rgb(15, 76, 129);">文件</strong></td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;"><strong style="line-height: 1.75;color: rgb(15, 76, 129);">作用</strong></td></tr></thead><tbody><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">gcBgMarkWorker</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime/mgc.go</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">标记协程主方法</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">gcMarkDone</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime/mgc.go</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">所有标记任务完成后处理</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">stopTheWorldWithSema</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime/proc.go</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">停止所有用户协程</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">gcMarkTermination</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime/mgc.go</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">进入标记终止阶段</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">gcSweep</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime/mgc.go</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">唤醒后台清扫协程</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">sweepone</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime/mgcsweep.go</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">每次清扫一个mspan</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">sweepLocked.sweep</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime/mgcsweep.go</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">完成mspan中的bitmap更新</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">startTheWorldWithSema</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime/proc.go</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">将所有用户协程恢复为可运行态</td></tr></tbody></table>  
  
   
## 6.1 标记完成  
  
在并发标记阶段的gcBgMarkWorker方法中，当最后一个标记协程也完成任务后，会调用gcMarkDone方法，开始执行并发标记后处理的逻辑.  
```
func gcBgMarkWorker() {
    // ...
    for{
        // ...
        if incnwait == work.nproc && !gcMarkWorkAvailable(nil) {
            // ...
            gcMarkDone()
        }
    }
}
```  
  
   
  
gcMarkDone方法中，会遍历释放所有P的写屏障缓存，查看是否存在因屏障机制遗留的灰色对象，如果有，则会推出gcMarkDone方法，回退到gcBgMarkWorker的主循环中，继续完成标记任务.  
  
倘若写屏障中也没有遗留的灰对象，此时会调用STW停止世界，并步入gcMarkTermination方法进入标记终止阶段.  
```
func gcMarkDone()
top:    
    if !(gcphase == _GCmark && work.nwait == work.nproc && !gcMarkWorkAvailable(nil)) {
        semrelease(&work.markDoneSema)
        return    
    }    
    // ...
    // 切换到 p0
    systemstack(func() {
        gp := getg().m.curg
        casgstatus(gp, _Grunning, _Gwaiting)
        forEachP(func(_p_ *p) {
            // 释放一波写屏障的缓存,可能会新的待标记任务产生            
            wbBufFlush1(_p_)
        })
        casgstatus(gp, _Gwaiting, _Grunning)
    })


    // 倘若有新的标记对象待处理，则调回 top 处，可能会回退到并发标记阶段
    if gcMarkDoneFlushed != 0 {
        // ...
        goto top
    }
    // 正式进入标记完成阶段，会STW
    systemstack(stopTheWorldWithSema)
    // ...
    // 在 STW 状态下，进入标记终止阶段
    gcMarkTermination()
}
```  
  
   
## 6.2 标记终止  
  
gcMarkTermination方法包括几个核心步骤：  
- • 设置GC进入标记终止阶段_GCmarktermination  
  
- • 切换至g0，设置GC进入标记关闭阶段_GCoff  
  
- • 切换至g0，调用gcSweep方法，唤醒后台清扫协程，执行标记清扫工作  
  
- • 切换至g0，执行gcControllerCommit方法，设置触发下一轮GC的内存阈值  
  
- • 切换至g0，调用startTheWorldWithSema方法，重启世界  
  
```
func gcMarkTermination() {


    // 设置GC阶段进入标记终止阶段
    setGCPhase(_GCmarktermination)
    // ...


    systemstack(func() {
       // ...
        // 设置GC阶段进入标记关闭阶段
        setGCPhase(_GCoff)  
        // 开始执行标记清扫动作     
        gcSweep(work.mode)
    })
   // 提交下一轮GC的内存阈值
   systemstack(gcControllerCommit)
   // ...
   systemstack(func() { startTheWorldWithSema(true) })
    // ...
}
```  
  
   
## 6.3 标记清扫  
  
gwSweep方法的核心是调用ready方法，唤醒了因为gopark操作陷入被动阻塞的清扫协程sweep.g.  
```
func gcSweep(mode gcMode) {
    assertWorldStopped()
   // ...


    // 唤醒后台清扫任务
    lock(&sweep.lock)
    if sweep.parked {
        sweep.parked = false
        ready(sweep.g, 0, true)
    }
    unlock(&sweep.lock)
}
```  
  
   
  
那么sweep.g是在何时被创建，又是在何时被park的呢？  
  
我们重新回到runtime包的main函数中，开始向下追溯：  
```
func main() {
    // ...
    gcenable()
    // ...
}
```  
  
   
```
func gcenable() {    
    // ...
    go bgsweep(c)
    <-c
    // ...
}
```  
  
   
  
可以看到，在异步启动的bgsweep方法中，会首先将当前协程gopark挂起，等待被唤醒.  
  
当在标记终止阶段被唤醒后，会进入for循环，每轮完成一个mspan的清扫工作，随后就调用Gosched方法主动让渡P的执行权，采用这种懒清扫的方式逐步推进标记清扫流程.  
```
func bgsweep(c chan int) {
    sweep.g = getg()


    lockInit(&sweep.lock, lockRankSweep)
    lock(&sweep.lock)
    sweep.parked = true
    c <- 1
    // 执行 gopark 操作，等待 GC 并发标记阶段完成后将当前协程唤醒
    goparkunlock(&sweep.lock, waitReasonGCSweepWait, traceEvGoBlock, 1)


    for {
        // 每清扫一个 mspan 后，会发起主动让渡
        for sweepone() != ^uintptr(0) {
            sweep.nbgsweep++
            Gosched()
        }
        // ...
        lock(&sweep.lock)
        if !isSweepDone() {
            // This can happen if a GC runs between
            // gosweepone returning ^0 above
            // and the lock being acquired.
            unlock(&sweep.lock)
            continue
        }
        // 清扫完成，则继续 gopark 被动阻塞
        sweep.parked = true
        goparkunlock(&sweep.lock, waitReasonGCSweepWait, traceEvGoBlock, 1)
    }
}
```  
  
   
  
sweepone方法每次清扫一个协程，清扫逻辑核心位于sweepLocked.sweep方法中，正是将mspan的gcmarkBits赋给allocBits，并创建出一个空白的bitmap作为新的gcmarkBits. 这一实现呼应了本文4.5小节谈到的设定.  
```
func sweepone() uintptr {
    // ...
    sl := sweep.active.begin()
    // ...
    for {
        // 查找到一个待清扫的 mspan
        s := mheap_.nextSpanForSweep()
        // ...
        if s, ok := sl.tryAcquire(s); ok {
            npages = s.npages
            // 对一个 mspan 进行清扫
            if s.sweep(false) {
                // Whole span was freed. Count it toward the
                // page reclaimer credit since these pages can
                // now be used for span allocation.
                mheap_.reclaimCredit.Add(npages)
            } else {
                // Span is still in-use, so this returned no
                // pages to the heap and the span needs to
                // move to the swept in-use list.
                npages = 0
            }
            break
        }
    }
    sweep.active.end(sl)


    // ...
    return npages
}
```  
  
   
```
func (sl *sweepLocked) sweep(preserve bool) bool {
    // ...
    s.allocBits = s.gcmarkBits
    s.gcmarkBits = newMarkBits(s.nelems)
    // ...
}
```  
  
   
## 6.4 设置下轮GC阈值  
  
在gcMarkTermination方法中，还会通过g0调用gcControllerCommit方法，完成下轮触发GC的内存阈值的设定.  
```
func gcMarkTermination() {
   // ... 
   // 提交下一轮GC的内存阈值
   systemstack(gcControllerCommit)
   // ...
}
```  
  
   
```
func gcControllerCommit() {
    assertWorldStoppedOrLockHeld(&mheap_.lock)


    gcController.commit(isSweepDone())
    // ...
}
```  
  
   
  
在gcControllerState.commit方法中，会读取gcControllerState.gcPercent字段值作为触发GC的堆使用内存增长比例，并结合当前堆内存的使用情况，推算出触发下轮GC的内存阈值，设置到gcControllerState.gcPercentHeapGoal字段中.  
```
func (c *gcControllerState) commit(isSweepDone bool) {
    // ...
    gcPercentHeapGoal := ^uint64(0)
    // gcPercent 值，用户可以通过环境变量 GOGC 显式设置. 未设时，默认值为 100.
    if gcPercent := c.gcPercent.Load(); gcPercent >= 0 {
        gcPercentHeapGoal = c.heapMarked + (c.heapMarked+atomic.Load64(&c.lastStackScan)+atomic.Load64(&c.globalsScan))*uint64(gcPercent)/100
    }
    // ...
    c.gcPercentHeapGoal.Store(gcPercentHeapGoal)
    // ...
}
```  
  
   
  
在新一轮尝试触发 GC 的过程中，对于gcTriggerHeap类型的触发事件，会调用gcController.trigger方法，读取到gcControllerState.gcPercentHeapGoal中存储的内存阈值，进行触发条件校验.  
```
func (t gcTrigger) test() bool {
    // ...
    switch t.kind {
        case gcTriggerHeap:
        // ...
            trigger, _ := gcController.trigger()
            return atomic.Load64(&gcController.heapLive) >= trigger
        // ...
    }
    return true
}
```  
  
   
```
func (c *gcControllerState) trigger() (uint64, uint64) {
    goal, minTrigger := c.heapGoalInternal()
    // ...
    var trigger uint64
    runway := c.runway.Load()
    // ...
    trigger = goal - runway
    // ...
    return trigger, goal
}
```  
  
   
```
func (c *gcControllerState) heapGoalInternal() (goal, minTrigger uint64) {    
    goal = c.gcPercentHeapGoal.Load()
    // ...
    return
}
```  
  
   
# 7 系统驻留内存清理  
  
Golang 进程从操作系统主内存（Random-Access Memory，简称 RAM）中申请到堆中进行复用的内存部分称为驻留内存（Resident Set Size，RSS）. 显然，RSS 不可能只借不还，应当遵循实际使用情况进行动态扩缩.  
  
Golang 运行时会异步启动一个回收协程，以趋近于 1% CPU 使用率作为目标，持续地对RSS中的空闲内存进行回收.  
  
   
## 7.1 回收协程启动  
  
在 runtime包下的main函数中，会异步启动回收协程bgscavenge，源码如下：  
```
func main() {
    // ...
    gcenable()
    // ...
}
```  
  
   
```
func gcenable() {    
    // ...
    go bgscavenge(c)
    <-c
    // ...
}
```  
  
   
## 7.2 执行频率控制  
  
在 bgscavenge 方法中，通过for循环 + sleep的方式，控制回收协程的执行频率在占用CPU 时间片的1%左右. 其中回收RSS的核心逻辑位于scavengerState.run方法.  
```
func bgscavenge(c chan int) {
    scavenger.init()


    c <- 1
    scavenger.park()
    // 如果当前操作系统分配内存＞目标内存
    for {
        // 释放内存
        released, workTime := scavenger.run()
        if released == 0 {
            scavenger.park()
            continue
        }
        atomic.Xadduintptr(&mheap_.pages.scav.released, released)
        scavenger.sleep(workTime)
    }
}
```  
  
   
## 7.3 回收空闲内存  
  
scavengerState.run方法中，会开启循环，经历pageAlloc.scavenge -> pageAlloc.scavengeOne 的调用链，最终通过sysUnused方法进行空闲内存页的回收.  
  
   
```
func (s *scavengerState) run() (released uintptr, worked float64) {
    // ...
    for worked < minScavWorkTime {
        // ...
        const scavengeQuantum = 64 << 10
        r, duration := s.scavenge(scavengeQuantum)
        // ...
    }
    return
}
```  
  
   
```
func (p *pageAlloc) scavenge(nbytes uintptr, shouldStop func() bool) uintptr {
    released := uintptr(0)
    for released < nbytes {
        ci, pageIdx := p.scav.index.find()
        if ci == 0 {
            break
        }
        systemstack(func() {
            released += p.scavengeOne(ci, pageIdx, nbytes-released)
        })
        if shouldStop != nil && shouldStop() {
            break
        }
    }
    return released
}
```  
  
   
  
在 pageAlloc.scavengeOne 方法中，通过findScavengeCandidate 方法寻找到待回收的页，通过 sysUnused 方法发起系统调用进行内存回收.  
```
func (p *pageAlloc) scavengeOne(ci chunkIdx, searchIdx uint, max uintptr) uintptr {
    // ...
    lock(p.mheapLock)
    if p.summary[len(p.summary)-1][ci].max() >= uint(minPages) {
        // 找到待回收的部分
        base, npages := p.chunkOf(ci).findScavengeCandidate(pallocChunkPages-1, minPages, maxPages)


        // If we found something, scavenge it and return!
        if npages != 0 {
            // Compute the full address for the start of the range.
            addr := chunkBase(ci) + uintptr(base)*pageSize
            // ...
            unlock(p.mheapLock)


            if !p.test {
                // 发起系统调用，回收内存
                sysUnused(unsafe.Pointer(addr), uintptr(npages)*pageSize)


                // 更新状态信息
                nbytes := int64(npages) * pageSize
                gcController.heapReleased.add(nbytes)
                gcController.heapFree.add(-nbytes)


                stats := memstats.heapStats.acquire()
                atomic.Xaddint64(&stats.committed, -nbytes)
                atomic.Xaddint64(&stats.released, nbytes)
                memstats.heapStats.release()
            }


            // 更新基数树信息
            lock(p.mheapLock)
            p.free(addr, uintptr(npages), true)
            p.chunkOf(ci).scavenged.setRange(base, npages)
            unlock(p.mheapLock)


            return uintptr(npages) * pageSize
        }
    }
   // 
}
```  
  
   
  
前文 Golang 内存模型与分配机制中，我们有介绍过，在 Golang 堆中会基于基数树的形式建立空闲页的索引，且基数树每个叶子节点对应了一个 chunk 块大小的内存(512 * 8KB = 4MB).  
  
其中chunk的封装类 pallocData 中有还两个核心字段，一个 pallocBits 中标识了一个页是否被占用了（1 占用、0空闲），同时还有另一个 scavenged bitmap 用于表示一个页是否已经被操作系统回收了（1 已回收、0 未回收）. 因此，回收协程的目标就是找到某个页，当其 pallocBits 和 scavenged 中的 bit 都为 0 时,代表其可以回收.  
  
由于回收时，可能需要同时回收多个页. 此时会利用基数树的特性,帮助快速找到连续的空闲可回收的页位置.  
```
type pallocData struct {
    pallocBits
    scavenged pageBits
}
```  
  
   
  
   
# 8 总结  
  
至此，Golang内存管理系列的三篇文章全部结束. 如有纰漏，欢迎批评指正.  
  
  
