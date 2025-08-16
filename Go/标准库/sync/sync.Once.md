![链接](https://mmbiz.qpic.cn/mmbiz_png/3ic3aBqT2ibZuGr4fyKR57PvlUA11pxAKpWw5gGk4VuEXa6Pyf7M8NmKPP7Eu9y9ocqkj512X6CSTY92QMEltrYg/640?wx_fmt=png&tp=wxpic&wxfrom=5&wx_lazy=1)
```go
package sync  
  
import (  
    "sync/atomic"  
)  
  
type Once struct {  
    // 通过一个整型变量标识，once 保护的函数是否已经被执行过  
    done uint32  
    // 一把锁，在并发场景下保护临界资源 done 字段只能串行访问  
    m    Mutex  
}

func (o *Once) Do(f func()) {  
    // 锁外的第一次 check，读取 Once.done 的值  
    if atomic.LoadUint32(&o.done) == 0 {  
        o.doSlow(f)  
    }  
}  
  
func (o *Once) doSlow(f func()) {  
    // 加锁  
    o.m.Lock()  
    defer o.m.Unlock()  
    // double check  
    if o.done == 0 {  
        // 任务执行完成后，将 Once.done 标识为 1  
        defer atomic.StoreUint32(&o.done, 1)  
        // 保证全局唯一一次执行用户注入的任务  
        f()  
    }  
}
```
- first check：第一次检查 Once.done 的值是否为 0，这步是无锁化的
- easy return：倘若 Once.done 的值为 0，说明任务已经执行过，直接返回
- lock：加锁
- double check：再次检查 Once.done 的值是否为 0
- execute func：倘若通过 double check，真正执行用户传入的执行函数 f
- update：执行完 f 后，将 Once.done 的值设为 1
- return：解锁并返回