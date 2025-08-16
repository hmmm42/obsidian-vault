#  Golang map 实现原理  
原创 小徐先生1212  小徐先生的编程世界   2023-01-06 23:26  
  
# 0 前言  
  
map 是一种如此经典的数据结构，各种语言中都对 map 着一套宏观流程相似、但技术细节百花齐放的实现方式.  
  
古语有云，大道至简，但这更多体现在原理和使用层面，从另一个角度而言，在认知上越基础的东西反而往往有着越复杂的实现细节.  
  
那么，诸位英雄好汉中又有哪几位有勇气随我一同深入 golang 的 map 源码，抱着【不通透不罢休】的态度，对其底层原理进行一探究竟呢？  
  
   
# 1 基本用法  
## 1.1 概述  
  
map 又称字典，是一种常用的数据结构，核心特征包含下述三点：  
  
（1）存储基于 key-value 对映射的模式；  
  
（2）基于 key 维度实现存储数据的去重；  
  
（3）读、写、删操作控制，时间复杂度 O(1).  
  
   
## 1.2 初始化  
### 1.2.1 几种初始化方法  
  
golang 中，对 map 的初始化分为以下几种方式：  
```
myMap1 := make(map[int]int,2)
```  
  
通过 make 关键字进行初始化，同时指定 map 预分配的容量.  
```
myMap2 := make(map[int]int)
```  
  
通过 make 关键字进行初始化，不显式声明容量，因此默认容量 为 0.  
```
myMap3 :=map[int]int{
  1:2,
  3:4,
}
```  
  
初始化操作连带赋值，一气呵成.  
  
   
### 1.2.2 key 的类型要求  
  
map 中，key 的数据类型必须为可比较的类型，chan、map、func不可比较  
  
   
## 1.3 读  
  
读 map 分为下面两种方式：  
```
v1 := myMap[10]
```  
  
第一种方式是直接读，倘若 key 存在，则获取到对应的 val，倘若 key 不存在或者 map 未初始化，会返回 val 类型的零值作为兜底.  
  
   
```
v2,ok := myMap[10]
```  
  
第二种方式是读的同时添加一个 bool 类型的 flag 标识是否读取成功. 倘若 ok == false，说明读取失败， key 不存在，或者 map 未初始化.  
  
   
  
此处同一种语法能够实现不同返回值类型的适配，是由于代码在汇编时，会根据返回参数类型的区别，映射到不同的实现方法.  
  
   
## 1.4 写  
```
myMap[5] = 6
```  
  
写操作的语法如上. 须注意的一点是，倘若 map 未初始化，直接执行写操作会导致 panic：  
```
const plainError string
panic(plainError("assignment to entry in nil map"))
```  
  
   
## 1.5 删  
```
delete(myMap,5)
```  
  
执行 delete 方法时，倘若 key 存在，则会从 map 中将对应的 key-value 对删除；倘若 key 不存在或 map 未初始化，则方法直接结束，不会产生显式提示.  
  
   
## 1.6 遍历  
  
遍历分为下面两种方式：  
```
for k,v := range myMap{
  // ...
}
```  
  
基于 k,v 依次承接 map 中的 key-value 对；  
  
   
```
for k := range myMap{
  // ...
}
```  
  
基于 k 依次承接 map 中的 key，不关注 val 的取值.  
  
需要注意的是，在执行 map 遍历操作时，获取的 key-value 对并没有一个固定的顺序，因此前后两次遍历顺序可能存在差异.  
  
   
## 1.7 并发冲突  
  
==map 不是并发安全的数据结构，倘若存在并发读写行为，会抛出 fatal error.  ==
  
具体规则是：  
  
（1）并发读没有问题；  
  
（2）并发读写中的“写”是广义上的，包含写入、更新、删除等操作；  
  
（3）读的时候发现其他 goroutine 在==并发写==，抛出 fatal error；  
  
（4）写的时候发现其他 goroutine 在==并发写==，抛出 fatal error.  
  
   
```
fatal("concurrent map read and map write")
fatal("concurrent map writes")
```  
  
需要关注，此处并发读写会引发 fatal error，是一种比 panic 更严重的错误，无法使用 recover 操作捕获.  
  
   
# 2 核心原理  
  
map 又称为 hash map，在算法上基于 hash 实现 key 的映射和寻址；在数据结构上基于桶数组实现 key-value 对的存储.  
  
以一组 key-value 对写入 map 的流程为例进行简述：  
  
（1）通过哈希方法取得 key 的 hash 值；  
  
（2）hash 值对桶数组长度取模，确定其所属的桶；  
  
（3）在桶中插入 key-value 对.  
  
   
  
hash 的性质，保证了相同的 key 必然产生相同的 hash 值，因此能映射到相同的桶中，通过桶内遍历的方式锁定对应的 key-value 对.  
  
因此，只要在宏观流程上，控制每个桶中 key-value 对的数量，就能保证 map 的几项操作都限制为常数级别的时间复杂度.  
  
   
  
![](https://mmbiz.qpic.cn/mmbiz_png/3ic3aBqT2ibZuARxegbGpWRTtYV5T52c5xAy07QRq8ZOtpucRqp3pxGD2Z8rl4d0zIW1xCChDw7d28xvIN2cHQUA/640?wx_fmt=png "")  
## 2.1 hash  
  
hash 译作散列，是一种将任意长度的输入压缩到某一固定长度的输出摘要的过程，由于这种转换属于压缩映射，输入空间远大于输出空间，因此不同输入可能会映射成相同的输出结果. 此外，hash在压缩过程中会存在部分信息的遗失，因此这种映射关系具有不可逆的特质.  
  
   
  
（1）hash 的可重入性：相同的 key，必然产生相同的 hash 值；  
  
（2）hash 的离散性：只要两个 key 不相同，不论其相似度的高低，产生的 hash 值会在整个输出域内均匀地离散化；  
  
   
  
![](https://mmbiz.qpic.cn/mmbiz_png/3ic3aBqT2ibZuARxegbGpWRTtYV5T52c5xrFiaFIdLpXicxWjHF3kVswzNLzLzpgFb2zndSdCGZp211Tlno5nk7VNA/640?wx_fmt=png "")  
  
   
  
（3）hash 的单向性：企图通过 hash 值反向映射回 key 是无迹可寻的.  
  
   
  
![](https://mmbiz.qpic.cn/mmbiz_png/3ic3aBqT2ibZuARxegbGpWRTtYV5T52c5xF5mTCAJ0cJkNtZIOSib0NDAd5zovB6CTfHzqW4dBwLqktNcr222QORg/640?wx_fmt=png "")  
  
   
  
（4）hash 冲突：由于输入域（key）无穷大，输出域（hash 值）有限，因此必然存在不同 key 映射到相同 hash 值的情况，称之为 hash 冲突.  
  
   
  
![](https://mmbiz.qpic.cn/mmbiz_png/3ic3aBqT2ibZuARxegbGpWRTtYV5T52c5x4ibdHHBfwicsgZ0KZCDKm1FJLpxocgMb67LvKECUUtB4lybhudKz92mA/640?wx_fmt=png "")  
  
   
## 2.2 桶数组  
  
map 中，会通过长度为 2 的整数次幂的桶数组进行 key-value 对的存储：  
  
（1）每个桶固定可以存放 8 个 key-value 对；  
  
（2）倘若超过 8 个 key-value 对打到桶数组的同一个索引当中，此时会通过创建桶链表的方式来化解这一问题.  
  
   
  
![](https://mmbiz.qpic.cn/mmbiz_png/3ic3aBqT2ibZuARxegbGpWRTtYV5T52c5x7UAUibf0DBUJ65tTQjr7hMzDWuicyFjvFD8ZpMz1ukjGgiaFGY20jotwA/640?wx_fmt=png "")  
  
   
## 2.3 拉链法解决 hash 冲突  
  
首先，由于 hash 冲突的存在，不同 key 可能存在相同的 hash 值；  
  
再者，hash 值会对桶数组长度取模，因此不同 hash 值可能被打到同一个桶中.  
  
综上，不同的 key-value 可能被映射到 map 的同一个桶当中.  
  
   
  
此时最经典的解决手段分为两种：拉链法和开放寻址法.  
  
   
  
（1）拉链法  
  
拉链法中，将命中同一个桶的元素通过链表的形式进行链接，因此很便于动态扩展.  
  
![](https://mmbiz.qpic.cn/mmbiz_png/3ic3aBqT2ibZuARxegbGpWRTtYV5T52c5xE1OOMuX5AIEtl6cQeibcKNf9v2YibSeK6rnsncJKxqZ47aKicwwhBq0iaA/640?wx_fmt=png "")  
  
   
  
   
  
（2）开放寻址法  
  
开放寻址法中，在插入新条目时，会基于一定的探测策略持续寻找，直到找到一个可用于存放数据的空位为止.  
  
![](https://mmbiz.qpic.cn/mmbiz_png/3ic3aBqT2ibZuARxegbGpWRTtYV5T52c5xs80iagnj3wyMuib1ga8lOmrW2H8F59qJWBZuZvb51CE3az291L8C0Dzg/640?wx_fmt=png "")  
  
   
  
   
  
对标拉链还有开放寻址法，两者的优劣对比：  
  
<table><thead style="line-height: 1.75;background: rgba(0, 0, 0, 0.05);font-weight: bold;color: rgb(63, 63, 63);"><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;"><strong style="line-height: 1.75;color: rgb(15, 76, 129);">方法</strong></td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;"><strong style="line-height: 1.75;color: rgb(15, 76, 129);">优点</strong></td></tr></thead><tbody><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">拉链法</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">简单常用；无需预先为元素分配内存.</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">开放寻址法</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">无需额外的指针用于链接元素；内存地址完全连续，可以基于局部性原理，充分利用 CPU 高速缓存.</td></tr></tbody></table>  
  

	 
  
在 map 解决 hash /分桶 冲突问题时，实际上**结合了拉链法和开放寻址法两种思路**. 以 map 的插入写流程为例，进行思路阐述：  
  
（1）桶数组中的每个桶，严格意义上是一个单向桶链表，以桶为节点进行串联；  
  
（2）每个桶固定可以存放 8 个 key-value 对；  
  
（3）当 key 命中一个桶时，首先根据开放寻址法，在桶的 8 个位置中寻找空位进行插入；  
  
（4）倘若桶的 8 个位置都已被占满，则基于桶的溢出桶指针，找到下一个桶，重复第（3）步；  
  
（5）倘若遍历到链表尾部，仍未找到空位，则基于拉链法，在桶链表尾部续接新桶，并插入 key-value 对.  
  
   
  
![](https://mmbiz.qpic.cn/mmbiz_png/3ic3aBqT2ibZuARxegbGpWRTtYV5T52c5xN7Wzw5RZxrMkgSHUV1KySs3vNb4K68Z4SKiaf0YkxBzxm35xXx4BaSg/640?wx_fmt=png "")  
  
   
## 2.4 扩容优化性能  
  
倘若 map 的桶数组长度固定不变，那么随着 key-value 对数量的增长，当一个桶下挂载的 key-value 达到一定的量级，此时操作的时间复杂度会趋于线性，无法满足诉求.  
  
因此在实现上，map 桶数组的长度会随着 key-value 对数量的变化而实时调整，以保证每个桶内的 key-value 对数量始终控制在常量级别，满足各项操作为 O(1) 时间复杂度的要求.  
  
map 扩容机制的核心点包括：  
  
（1）扩容分为增量扩容和等量扩容；  
  
（2）当桶内 key-value 总数/桶数组长度 > 6.5 时发生增量扩容，桶数组长度增长为原值的两倍；  
  
（3）当桶内溢出桶数量大于等于 2^B 时( B 为桶数组长度的指数，B 最大取 15)，发生等量扩容，桶的长度保持为原值；  **就是部分数据被删除, 间隙太多**
  
（4）采用渐进扩容的方式，当桶被实际操作到时，由使用者负责完成数据迁移，避免因为一次性的全量数据迁移引发性能抖动.  
  
  
![](https://mmbiz.qpic.cn/mmbiz_png/3ic3aBqT2ibZuARxegbGpWRTtYV5T52c5xKMnlcAK8ZnBea863au90G20QM9m2vXAvrLpa5iaibOQaibnPGyVkvrG2A/640?wx_fmt=png "")  
  
   
# 3 数据结构  
## 3.1 hmap  
  
![](https://mmbiz.qpic.cn/mmbiz_png/3ic3aBqT2ibZuARxegbGpWRTtYV5T52c5x81hicw2xUichvfsXX8zNkpVmJ9Gib1RJeA6rKOYNHXqSBrraSiaeMewGbg/640?wx_fmt=png "")  
  
   
  
   
```
type hmap struct {
    count     int 
    flags     uint8
    B         uint8  
    noverflow uint16 
    hash0     uint32 
    buckets    unsafe.Pointer 
    oldbuckets unsafe.Pointer 
    nevacuate  uintptr       
    extra *mapextra 
}
```  
  
（1）count：map 中的 key-value 总数；  
  
（2）flags：map 状态标识，可以标识出 map 是否被 goroutine 并发读写；  
  
（3）B：桶数组长度的指数，桶数组长度为 2^B；  
  
（4）noverflow：map 中溢出桶的数量；  
  
（5）hash0：hash 随机因子，生成 key 的 hash 值时会使用到；  
  
（6）buckets：桶数组；  
  
（7）oldbuckets：扩容过程中老的桶数组；  
  
（8）nevacuate：扩容时的进度标识，index 小于 nevacuate 的桶都已经由老桶转移到新桶中；  
  
（9）extra：预申请的溢出桶.  
  
   
## 3.2 mapextra  
  
![](https://mmbiz.qpic.cn/mmbiz_png/3ic3aBqT2ibZuARxegbGpWRTtYV5T52c5xVBxzza1lT8VeISlJW63XTQhdcHf8k2376I07lamIWKyTib0iccEaGkMQ/640?wx_fmt=png "")  
```
type mapextra struct {
    overflow    *[]*bmap
    oldoverflow *[]*bmap


    nextOverflow *bmap
}
```  
  
在 map 初始化时，倘若容量过大，会提前申请好一批溢出桶，以供后续使用，这部分溢出桶存放在 hmap.mapextra 当中：  
  
（1）mapextra.overflow：供桶数组 buckets 使用的溢出桶；  
  
（2）mapextra.oldoverFlow: 扩容流程中，供老桶数组 oldBuckets 使用的溢出桶；  
  
（3）mapextra.nextOverflow：下一个可用的溢出桶.  
  
   
## 3.3 bmap  
  
![](https://mmbiz.qpic.cn/mmbiz_png/3ic3aBqT2ibZuARxegbGpWRTtYV5T52c5xpfkKXezrzouDObRClehoILB8AYib0Kt1piaiahHib5pSN2EnFPn6RwbwtA/640?wx_fmt=png "")  
```
const bucketCnt = 8
type bmap struct {
    tophash [bucketCnt]uint8
}
```  
  
（1）bmap 就是 map 中的桶，可以存储 8 组 key-value 对的数据，以及一个指向下一个溢出桶的指针；  
  
（2）每组 key-value 对数据包含 key 高 8 位 hash 值 tophash，key 和 val 三部分；  
  
（3）在代码层面只展示了 tophash 部分，但由于 tophash、key 和 val 的数据长度固定，因此可以通过内存地址偏移的方式寻找到后续的 key 数组、val 数组以及溢出桶指针；  
  
（4）为方便理解，把完整的 bmap 类声明代码补充如下：  
```
type bmap struct {
    tophash [bucketCnt]uint8
    keys [bucketCnt]T
    values [bucketCnt]T
    overflow uint8
}
```  
# 4 构造方法  
  
![](https://mmbiz.qpic.cn/mmbiz_png/3ic3aBqT2ibZuARxegbGpWRTtYV5T52c5xjyPiaLXxITu6DCUvs6XQ6IRI1CdMoKU2cadficLhXro3bEHFSCGAxHjA/640?wx_fmt=png "")  
  
创建 map 时，实际上会调用 runtime/map.go 文件中的 makemap 方法，下面对源码展开分析：  
## 4.1 makemap  
  
方法主干源码一览：  
```
func makemap(t *maptype, hint int, h *hmap) *hmap {
    mem, overflow := math.MulUintptr(uintptr(hint), t.bucket.size)
    if overflow || mem > maxAlloc {
        hint = 0
    }


    if h == nil {
        h = new(hmap)
    }
    h.hash0 = fastrand()


    B := uint8(0)
    for overLoadFactor(hint, B) {
        B++
    }
    h.B = B


    if h.B != 0 {
        var nextOverflow *bmap
        h.buckets, nextOverflow = makeBucketArray(t, h.B, nil)
        if nextOverflow != nil {
            h.extra = new(mapextra)
            h.extra.nextOverflow = nextOverflow
        }
    }


    return 
```  
  
   
  
（1）hint 为 map 拟分配的容量；在分配前，会提前对拟分配的内存大小进行判断，倘若超限，会将 hint 置为零；  
```
mem, overflow := math.MulUintptr(uintptr(hint), t.bucket.size)
if overflow || mem > maxAlloc {
   hint = 0
}
```  
  
   
  
（2）通过 new 方法初始化 hmap；  
```
if h == nil {
   h = new(hmap)
}
```  
  
   
  
（3）调用 fastrand，构造 hash 因子：hmap.hash0；  
```
h.hash0 = fastrand()
```  
  
   
  
（4）大致上基于 log2(B) >= hint 的思路（具体见 4.2 小节 overLoadFactor 方法的介绍），计算桶数组的容量 B；  
```
B := uint8(0)
for overLoadFactor(hint, B) {
    B++
}
h.B =
```  
  
   
  
（5）调用 makeBucketArray 方法，初始化桶数组 hmap.buckets；  
```
var nextOverflow *bmap
h.buckets, nextOverflow = makeBucketArray(t, h.B, n
```  
  
   
  
（6）倘若 map 容量较大，会提前申请一批溢出桶 hmap.extra.  
```
if nextOverflow != nil {
   h.extra = new(mapextra)
   h.extra.nextOverflow = nextOverflow
}
```  
  
   
## 4.2 overLoadFactor  
  
通过 overLoadFactor 方法，对 map 预分配容量和桶数组长度指数进行判断，决定是否仍需要增长 B 的数值：  
```
const loadFactorNum = 13
const loadFactorDen = 2
const goarch.PtrSize = 8
const bucketCnt = 8


func overLoadFactor(count int, B uint8) bool {
    return count > bucketCnt && uintptr(count) > loadFactorNum*(bucketShift(B)/loadFactorDen)
}


func bucketShift(b uint8) uintptr {
    return uintptr(1) << (b & (goarch.PtrSize*8 - 1))
```  
  
（1）倘若 map 预分配容量小于等于 8，B 取 0，桶的个数为 1；  
  
（2）保证 map 预分配容量小于等于桶数组长度 * 6.5.  
  
   
  
map 预分配容量、桶数组长度指数、桶数组长度之间的关系如下表：  
  
<table><thead style="line-height: 1.75;background: rgba(0, 0, 0, 0.05);font-weight: bold;color: rgb(63, 63, 63);"><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;"><strong style="line-height: 1.75;color: rgb(15, 76, 129);">kv 对数量</strong></td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;"><strong style="line-height: 1.75;color: rgb(15, 76, 129);">桶数组长度指数 B</strong></td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;"><strong style="line-height: 1.75;color: rgb(15, 76, 129);">桶数组长度 2^B</strong></td></tr></thead><tbody><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">0 ~ 8</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">0</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">1</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">9 ~ 13</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">1</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">2</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">14 ~ 26</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">2</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">4</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">27 ~ 52</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">3</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">8</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">2^(B-1) * 6.5+1 ~ 2^B*6.5</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">B</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">2^B</td></tr></tbody></table>  
  

	 
## 4.3 makeBucketArray  
  
makeBucketArray 方法会进行桶数组的初始化，并根据桶的数量决定是否需要提前作溢出桶的初始化. 方法主干代码如下：  
```
func makeBucketArray(t *maptype, b uint8, dirtyalloc unsafe.Pointer) (buckets unsafe.Pointer, nextOverflow *bmap) {
    base := bucketShift(b)
    nbuckets := base
    if b >= 4 {
        nbuckets += bucketShift(b - 4)
    }
    
    buckets = newarray(t.bucket, int(nbuckets))
   
    if base != nbuckets {
        nextOverflow = (*bmap)(add(buckets, base*uintptr(t.bucketsize)))
        last := (*bmap)(add(buckets, (nbuckets-1)*uintptr(t.bucketsize)))
        last.setoverflow(t, (*bmap)(buckets))
    }
    return buckets, nextOverflow
}
```  
  
   
  
makeBucketArray 会为 map 的桶数组申请内存，在桶数组的指数 b >= 4时（桶数组的容量 >= 52 ），会需要提前创建溢出桶.  
  
通过 base 记录桶数组的长度，不包含溢出桶；通过 nbuckets 记录累加上溢出桶后，桶数组的总长度.  
  
   
```
base := bucketShift(b)
nbuckets := base
if b >= 4 {
   nbuckets += bucketShift(b - 4)
}
```  
  
   
  
调用 newarray 方法为桶数组申请内存空间，连带着需要初始化的溢出桶：  
```
buckets = newarray(t.bucket, int(nbuckets))
```  
  
   
  
倘若 base != nbuckets，说明需要创建溢出桶，会基于地址偏移的方式，通过 nextOverflow 指向首个溢出桶的地址.  
```
if base != nbuckets {
   nextOverflow = (*bmap)(add(buckets, base*uintptr(t.bucketsize)))
   last := (*bmap)(add(buckets, (nbuckets-1)*uintptr(t.bucketsize)))
   last.setoverflow(t, (*bmap)(buckets))
}
return buckets, nextOverflow
```  
  
   
  
倘若需要创建溢出桶，会在将最后一个溢出桶的 overflow 指针指向 buckets 数组，以此来标识申请的溢出桶已经用完.  
```
func (b *bmap) setoverflow(t *maptype, ovf *bmap) {
    *(**bmap)(add(unsafe.Pointer(b), uintptr(t.bucketsize)-goarch.PtrSize)) = ovf
}
```  
# 5 读流程  
  
![](https://mmbiz.qpic.cn/mmbiz_png/3ic3aBqT2ibZuARxegbGpWRTtYV5T52c5xfUNhlneXoL9DIWD6vC847icJ5UzI3WDZreNWd0aALSlVNJCSrp1qkbA/640?wx_fmt=png "")  
  
   
## 5.1 读流程梳理  
  
map 读流程主要分为以下几步：  
  
（1）根据 key 取 hash 值；  
  
（2）根据 hash 值对桶数组取模，确定所在的桶；  
  
（3）沿着桶链表依次遍历各个桶内的 key-value 对；  
  
（4）命中相同的 key，则返回 value；倘若 key 不存在，则返回零值.  
  
map 读操作最终会走进 runtime/map.go 的 mapaccess 方法中，下面开始阅读源码：  
  
   
## 5.2 mapaccess 方法源码走读  
```
func mapaccess1(t *maptype, h *hmap, key unsafe.Pointer) unsafe.Pointer {
    if h == nil || h.count == 0 {
        return unsafe.Pointer(&zeroVal[0])
    }
    if h.flags&hashWriting != 0 {
        fatal("concurrent map read and map write")
    }
    hash := t.hasher(key, uintptr(h.hash0))
    m := bucketMask(h.B)
    b := (*bmap)(add(h.buckets, (hash&m)*uintptr(t.bucketsize)))
    if c := h.oldbuckets; c != nil {
        if !h.sameSizeGrow() {
            m >>= 1
        }
        oldb := (*bmap)(add(c, (hash&m)*uintptr(t.bucketsize)))
        if !evacuated(oldb) {
            b = oldb
        }
    }
    top := tophash(hash)
bucketloop:
    for ; b != nil; b = b.overflow(t) {
        for i := uintptr(0); i < bucketCnt; i++ {
            if b.tophash[i] != top {
                if b.tophash[i] == emptyRest {
                    break bucketloop
                }
                continue
            }
            k := add(unsafe.Pointer(b), dataOffset+i*uintptr(t.keysize))
            if t.indirectkey() {
                k = *((*unsafe.Pointer)(k))
            }
            if t.key.equal(key, k) {
                e := add(unsafe.Pointer(b), dataOffset+bucketCnt*uintptr(t.keysize)+i*uintptr(t.elemsize))
                if t.indirectelem() {
                    e = *((*unsafe.Pointer)(e))
                }
                return e
            }
        }
    }
    return unsafe.Pointer(&zeroVal[0])
}


func (h *hmap) sameSizeGrow() bool {
    return h.flags&sameSizeGrow != 0
}


func evacuated(b *bmap) bool {
    h := b.tophash[0]
    return h > emptyOne && h < minTopHash
}
```  
  
   
  
（1）倘若 map 未初始化，或此时存在 key-value 对数量为 0，直接返回零值；  
```
if h == nil || h.count == 0 {
    return unsafe.Pointer(&zeroVal[0])
}
```  
  
   
  
（2）倘若发现存在其他 goroutine 在写 map，直接抛出并发读写的 fatal error；其中，并发写标记，位于 hmap.flags 的第 3 个 bit 位；  
```
 const hashWriting  = 4
 
 if h.flags&hashWriting != 0 {
        fatal("concurrent map read and map write")
 }
```  
  
   
  
（3）通过 maptype.hasher() 方法计算得到 key 的 hash 值，并对桶数组长度取模，取得对应的桶. 关于 hash 方法的内部实现，golang 并未暴露.  
```
 hash := t.hasher(key, uintptr(h.hash0))
 m := bucketMask(h.B)
 b := (*bmap)(add(h.buckets, (hash&m)*uintptr(t.bucketsize))
```  
  
   
  
其中，bucketMast 方法会根据 B 求得桶数组长度 - 1 的值，用于后续的 & 运算，实现取模的效果：  
```
func bucketMask(b uint8) uintptr {
    return bucketShift(b) - 1
}
```  
  
   
  
（4）在取桶时，会关注当前 map 是否处于扩容的流程，倘若是的话，需要在老的桶数组 oldBuckets 中取桶，通过 evacuated 方法判断桶数据是已迁到新桶还是仍存留在老桶，倘若仍在老桶，需要取老桶进行遍历.  
```
 if c := h.oldbuckets; c != nil {
    if !h.sameSizeGrow() {
        m >>= 1
    }
    oldb := (*bmap)(add(c, (hash&m)*uintptr(t.bucketsize)))
    if !evacuated(oldb) {
        b = oldb
    }
 }
```  
  
   
  
在取老桶前，会先判断 map 的扩容流程是否是增量扩容，倘若是的话，说明老桶数组的长度是新桶数组的一半，需要将桶长度值 m 除以 2.  
```
const (
    sameSizeGrow = 8
)


func (h *hmap) sameSizeGrow() bool {
    return h.flags&sameSizeGrow != 0
}
```  
  
   
  
取老桶时，会调用 evacuated 方法判断数据是否已经迁移到新桶. 判断的方式是，取桶中首个 tophash 值，倘若该值为 2,3,4 中的一个，都代表数据已经完成迁移.  
```
const emptyOne = 1
const evacuatedX = 2
const evacuatedY = 3
const evacuatedEmpty = 4 
const minTopHash = 5


func evacuated(b *bmap) bool {
    h := b.tophash[0]
    return h > emptyOne && h < minTopHash
}
```  
  
   
  
（5）取 key hash 值的高 8 位值 top. 倘若该值 < 5，会累加 5，以避开 0 ~ 4 的取值. 因为这几个值会用于枚举，具有一些特殊的含义.  
```
const minTopHash = 5


top := tophash(hash)


func tophash(hash uintptr) uint8 {
    top := uint8(hash >> (goarch.PtrSize*8 - 8))
    if top < minTopHash {
        top += minTopHash
    }
    return top
```  
  
   
  
（6）开启两层 for 循环进行遍历流程，外层基于桶链表，依次遍历首个桶和后续的每个溢出桶，内层依次遍历一个桶内的 key-value 对.  
```
bucketloop:
for ; b != nil; b = b.overflow(t) {
    for i := uintptr(0); i < bucketCnt; i++ {
        // ...
    }
}
return unsafe.Pointer(&zeroVal[0])
```  
  
   
  
内存遍历时，首先查询高 8 位的 tophash 值，看是否和 key 的 top 值匹配.  
  
倘若不匹配且当前位置 tophash 值为 0，说明桶的后续位置都未放入过元素，当前 key 在 map 中不存在，可以直接打破循环，返回零值.  
```
const emptyRest = 0
if b.tophash[i] != top {
    if b.tophash[i] == emptyRest {
          break bucketloop
    }
    continue
}
```  
  
   
  
倘若找到了相等的 key，则通过地址偏移的方式取到 value 并返回.  
  
其中 dataOffset 为一个桶中 tophash 数组所占用的空间大小.  
```
if t.key.equal(key, k) {
     e := add(unsafe.Pointer(b), dataOffset+bucketCnt*uintptr(t.keysize)+i*uintptr(t.elemsize))
     return e
}
```  
  
倘若遍历完成，仍未找到匹配的目标，返回零值兜底.  
  
   
# 6 写流程  
  
![](https://mmbiz.qpic.cn/mmbiz_png/3ic3aBqT2ibZuARxegbGpWRTtYV5T52c5xQC9fQYDemJyrU5y1l8NDsiaUicLNv4MbHfHcADTczuQibtTDZDXetXZ8A/640?wx_fmt=png "")  
## 6.1 写流程梳理  
  
map 写流程主要分为以下几步：  
  
（1）根据 key 取 hash 值；  
  
（2）根据 hash 值对桶数组取模，确定所在的桶；  
  
（3）倘若 map 处于扩容，则迁移命中的桶，帮助推进渐进式扩容；  
  
（4）沿着桶链表依次遍历各个桶内的 key-value 对；  
  
（5）倘若命中相同的 key，则对 value 中进行更新；  
  
（6）倘若 key 不存在，则插入 key-value 对；  
  
（7）倘若发现 map 达成扩容条件，则会开启扩容模式，并重新返回第（2）步.  
  
   
  
map 写操作最终会走进 runtime/map.go 的 mapassign 方法中，下面开始阅读源码：  
  
   
## 6.2 mapassign  
```
func mapassign(t *maptype, h *hmap, key unsafe.Pointer) unsafe.Pointer {
    if h == nil {
        panic(plainError("assignment to entry in nil map"))
    }
    if h.flags&hashWriting != 0 {
        fatal("concurrent map writes")
    }
    hash := t.hasher(key, uintptr(h.hash0))


    h.flags ^= hashWriting


    if h.buckets == nil {
        h.buckets = newobject(t.bucket) 
    }


again:
    bucket := hash & bucketMask(h.B)
    if h.growing() {
        growWork(t, h, bucket)
    }
    b := (*bmap)(add(h.buckets, bucket*uintptr(t.bucketsize)))
    top := tophash(hash)


    var inserti *uint8
    var insertk unsafe.Pointer
    var elem unsafe.Pointer
bucketloop:
    for {
        for i := uintptr(0); i < bucketCnt; i++ {
            if b.tophash[i] != top {
                if isEmpty(b.tophash[i]) && inserti == nil {
                    inserti = &b.tophash[i]
                    insertk = add(unsafe.Pointer(b), dataOffset+i*uintptr(t.keysize))
                    elem = add(unsafe.Pointer(b), dataOffset+bucketCnt*uintptr(t.keysize)+i*uintptr(t.elemsize))
                }
                if b.tophash[i] == emptyRest {
                    break bucketloop
                }
                continue
            }
            k := add(unsafe.Pointer(b), dataOffset+i*uintptr(t.keysize))
            if t.indirectkey() {
                k = *((*unsafe.Pointer)(k))
            }
            if !t.key.equal(key, k) {
                continue
            }
            if t.needkeyupdate() {
                typedmemmove(t.key, k, key)
            }
            elem = add(unsafe.Pointer(b), dataOffset+bucketCnt*uintptr(t.keysize)+i*uintptr(t.elemsize))
            goto done
        }
        ovf := b.overflow(t)
        if ovf == nil {
            break
        }
        b = ovf
    }


    if !h.growing() && (overLoadFactor(h.count+1, h.B) || tooManyOverflowBuckets(h.noverflow, h.B)) {
        hashGrow(t, h)
        goto again 
    }


    if inserti == nil {
        newb := h.newoverflow(t, b)
        inserti = &newb.tophash[0]
        insertk = add(unsafe.Pointer(newb), dataOffset)
        elem = add(insertk, bucketCnt*uintptr(t.keysize))
    }


    if t.indirectkey() {
        kmem := newobject(t.key)
        *(*unsafe.Pointer)(insertk) = kmem
        insertk = kmem
    }
    if t.indirectelem() {
        vmem := newobject(t.elem)
        *(*unsafe.Pointer)(elem) = vmem
    }
    typedmemmove(t.key, insertk, key)
    *inserti = top
    h.count++




done:
    if h.flags&hashWriting == 0 {
        fatal("concurrent map writes")
    }
    h.flags &^= hashWriting
    if t.indirectelem() {
        elem = *((*unsafe.Pointer)(elem))
    }
    retur
```  
  
   
  
（1）写操作时，倘若 map 未初始化，直接 panic；  
```
if h == nil {
        panic(plainError("assignment to entry in nil map"))
}
```  
  
   
  
（2）倘若其他 goroutine 在进行写或删操作，抛出并发写 fatal error；  
```
if h.flags&hashWriting != 0 {
    fatal("concurrent map writes")
}
```  
  
   
  
（3）通过 maptype.hasher() 方法求得 key 对应的 hash 值；  
```
 hash := t.hasher(key, uintptr(h.hash0))
```  
  
   
  
（4）通过异或位运算，将 map.flags 的第 3 个 bit 位置为 1，添加写标记；  
```
h.flags ^= hashWriting
```  
  
   
  
（5）倘若 map 的桶数组 buckets 未空，则对其进行初始化；  
```
if h.buckets == nil {
     h.buckets = newobject(t.bucket) 
}
```  
  
   
  
（6）找到当前 key 对应的桶索引 bucket；  
```
bucket := hash & bucketMask(h.B)
```  
  
   
  
（7）倘若发现当前 map 正处于扩容过程，则帮助其渐进扩容，具体内容在第 9 节中再作展开；  
```
   if h.growing() {
        growWork(t, h, bucket)
  }
```  
  
   
  
（8）从 map 的桶数组 buckets 出发，结合桶索引和桶容量大小，进行地址偏移，获得对应桶 b；  
```
b := (*bmap)(add(h.buckets, bucket*uintptr(t.bucketsize)))
```  
  
   
  
（9）取得 key 的高 8 位 tophash：  
```
top := tophash(hash)
```  
  
   
  
（10）提前声明好的三个指针，用于指向存放 key-value 的空槽:  
  
inserti：tophash 拟插入位置；  
  
insertk：key 拟插入位置 ；  
  
elem：val 拟插入位置；  
```
var inserti *uint8
var insertk unsafe.Pointer
var elem unsafe.Pointer
```  
  
   
  
（11）开启两层 for 循环，外层沿着桶链表依次遍历，内层依次遍历桶内的 key-value 对：  
```
bucketloop:
    for {
        for i := uintptr(0); i < bucketCnt; i++ {
            // ...
        }
        ovf := b.overflow(t)
        if ovf == nil {
            break
        }
        b = ovf
     }
```  
  
   
  
(12）倘若 key 的 tophash 和当前位置 tophash 不同，则会尝试将 inserti、insertk elem 调整指向首个空位，用于后续的插入操作.  
  
倘若发现当前位置 tophash 标识为 emtpyRest（0），则说明当前桶链表后续位置都未空，无需继续遍历，直接 break 遍历流程即可.  
```
if b.tophash[i] != top {
      if isEmpty(b.tophash[i]) && inserti == nil {
                    inserti = &b.tophash[i]
                    insertk = add(unsafe.Pointer(b), dataOffset+i*uintptr(t.keysize))
                    elem = add(unsafe.Pointer(b), dataOffset+bucketCnt*uintptr(t.keysize)+i*uintptr(t.elemsize))
                }
                if b.tophash[i] == emptyRest {
                    break bucketloop
                }
                continue
         }
}
```  
  
   
  
倘若桶中某个位置的 tophash 标识为 emptyOne（1），说明当前位置未放入元素，倘若为 emptyRest（0），说明包括当前位置在内，此后的位置都为空.  
```
const emptyRest = 0 
const emptyOne = 1 


func isEmpty(x uint8) bool {
    return x <= emptyOne
}
```  
  
   
  
（13）倘若找到了相等的 key，则执行更新操作，并且直接跳转到方法的 done 标志位处，进行收尾处理；  
```
    k := add(unsafe.Pointer(b), dataOffset+i*uintptr(t.keysize))
    if t.indirectkey() {
         k = *((*unsafe.Pointer)(k))
    }
    if !t.key.equal(key, k) {
        continue
    }
    elem = add(unsafe.Pointer(b), dataOffset+bucketCnt*uintptr(t.keysize)+i*uintptr(t.elemsize))
    goto done
```  
  
   
  
（14）倘若没找到相等的 key，会在执行插入操作前，判断 map 是否需要开启扩容模式. 这部分内容在第 9 节中作展开.  
  
倘若需要扩容，会在开启扩容模式后，跳转回 again 标志位，重新开始桶的定位以及遍历流程.  
```
    if !h.growing() && (overLoadFactor(h.count+1, h.B) || tooManyOverflowBuckets(h.noverflow, h.B)) {
        hashGrow(t, h)
        goto again 
    }
```  
  
   
  
（15）倘若遍历完桶链表，都没有为当前待插入的 key-value 对找到空位，则会创建一个新的溢出桶，挂载在桶链表的尾部，并将 inserti、insertk、elem 指向溢出桶的首个空位：  
```
    if inserti == nil {
        newb := h.newoverflow(t, b)
        inserti = &newb.tophash[0]
        insertk = add(unsafe.Pointer(newb), dataOffset)
        elem = add(insertk, bucketCnt*uintptr(t.keysize))
    }
```  
  
   
  
创建溢出桶时：  
  
![](https://mmbiz.qpic.cn/mmbiz_png/3ic3aBqT2ibZuARxegbGpWRTtYV5T52c5xgjib724BtVu6WUseExIOlSqJXNKxSahocdhwmibGPrA1aBBS5kAQQfDg/640?wx_fmt=png "")  
  
I 倘若 hmap.extra 中还有剩余可用的溢出桶，则直接获取 hmap.extra.nextOverflow，并将 nextOverflow 调整指向下一个空闲可用的溢出桶；  
  
II 倘若 hmap 已经没有空闲溢出桶了，则创建一个新的溢出桶.  
  
III hmap 的溢出桶数量 hmap.noverflow 累加 1；  
  
IV 将新获得的溢出桶添加到原桶链表的尾部；  
  
V 返回溢出桶.  
  
   
```
func (h *hmap) newoverflow(t *maptype, b *bmap) *bmap {
    var ovf *bmap
    if h.extra != nil && h.extra.nextOverflow != nil {
        ovf = h.extra.nextOverflow
        if ovf.overflow(t) == nil {
            h.extra.nextOverflow = (*bmap)(add(unsafe.Pointer(ovf), uintptr(t.bucketsize)))
        } else {
            ovf.setoverflow(t, nil)
            h.extra.nextOverflow = nil
        }
    } else {
        ovf = (*bmap)(newobject(t.bucket))
    }
    h.incrnoverflow()
    if t.bucket.ptrdata == 0 {
        h.createOverflow()
        *h.extra.overflow = append(*h.extra.overflow, ovf)
    }
    b.setoverflow(t, ovf)
    return ovf
}
```  
  
   
  
（16）将 tophash、key、value 插入到取得空位中，并且将 map 的 key-value 对计数器 count 值加 1；  
```
    if t.indirectkey() {
        kmem := newobject(t.key)
        *(*unsafe.Pointer)(insertk) = kmem
        insertk = kmem
    }
    if t.indirectelem() {
        vmem := newobject(t.elem)
        *(*unsafe.Pointer)(elem) = vmem
    }
    typedmemmove(t.key, insertk, key)
    *inserti = top
    h.count++
```  
  
   
  
（17）收尾环节，再次校验是否有其他协程并发写，倘若有，则抛 fatal error. 将 hmap.flags 中的写标记抹去，然后退出方法.  
```
done:
    if h.flags&hashWriting == 0 {
        fatal("concurrent map writes")
    }
    h.flags &^= hashWriting
    if t.indirectelem() {
        elem = *((*unsafe.Pointer)(elem))
    }
    return elem
```  
  
   
  
   
# 7 删流程  
  
![](https://mmbiz.qpic.cn/mmbiz_png/3ic3aBqT2ibZuARxegbGpWRTtYV5T52c5xCApLEbibEJUg5CTHYNgJeH8nw6X2ibtLkWm55ia8MBXmkmmoCaMsPwtwg/640?wx_fmt=png "")  
## 7.1 删除 kv 对流程梳理  
  
map 删楚 kv 对流程主要分为以下几步：  
  
（1）根据 key 取 hash 值；  
  
（2）根据 hash 值对桶数组取模，确定所在的桶；  
  
（3）倘若 map 处于扩容，则迁移命中的桶，帮助推进渐进式扩容；  
  
（4）沿着桶链表依次遍历各个桶内的 key-value 对；  
  
（5）倘若命中相同的 key，删除对应的 key-value 对；并将当前位置的 tophash 置为 emptyOne，表示为空；  
  
（6）倘若当前位置为末位，或者下一个位置的 tophash 为 emptyRest，则沿当前位置向前遍历，将毗邻的 emptyOne 统一更新为 emptyRest.  
  
   
  
map 删操作最终会走进 runtime/map.go 的 mapdelete 方法中，下面开始阅读源码：  
  
   
## 7.2 mapdelete  
```
func mapdelete(t *maptype, h *hmap, key unsafe.Pointer) {
    if h == nil || h.count == 0 {
        return
    }
    if h.flags&hashWriting != 0 {
        fatal("concurrent map writes")
    }


    hash := t.hasher(key, uintptr(h.hash0))


    h.flags ^= hashWriting


    bucket := hash & bucketMask(h.B)
    if h.growing() {
        growWork(t, h, bucket)
    }
    b := (*bmap)(add(h.buckets, bucket*uintptr(t.bucketsize)))
    bOrig := b
    top := tophash(hash)
search:
    for ; b != nil; b = b.overflow(t) {
        for i := uintptr(0); i < bucketCnt; i++ {
            if b.tophash[i] != top {
                if b.tophash[i] == emptyRest {
                    break search
                }
                continue
            }
            k := add(unsafe.Pointer(b), dataOffset+i*uintptr(t.keysize))
            k2 := k
            if t.indirectkey() {
                k2 = *((*unsafe.Pointer)(k2))
            }
            if !t.key.equal(key, k2) {
                continue
            }
            // Only clear key if there are pointers in it.
            if t.indirectkey() {
                *(*unsafe.Pointer)(k) = nil
            } else if t.key.ptrdata != 0 {
                memclrHasPointers(k, t.key.size)
            }
            e := add(unsafe.Pointer(b), dataOffset+bucketCnt*uintptr(t.keysize)+i*uintptr(t.elemsize))
            if t.indirectelem() {
                *(*unsafe.Pointer)(e) = nil
            } else if t.elem.ptrdata != 0 {
                memclrHasPointers(e, t.elem.size)
            } else {
                memclrNoHeapPointers(e, t.elem.size)
            }
            b.tophash[i] = emptyOne
            if i == bucketCnt-1 {
                if b.overflow(t) != nil && b.overflow(t).tophash[0] != emptyRest {
                    goto notLast
                }
            } else {
                if b.tophash[i+1] != emptyRest {
                    goto notLast
                }
            }
            for {
                b.tophash[i] = emptyRest
                if i == 0 {
                    if b == bOrig {
                        break
                    }
                    c := b
                    for b = bOrig; b.overflow(t) != c; b = b.overflow(t) {
                    }
                    i = bucketCnt - 1
                } else {
                    i--
                }
                if b.tophash[i] != emptyOne {
                    break
                }
            }
        notLast:
            h.count--
            if h.count == 0 {
                h.hash0 = fastrand()
            }
            break search
        }
    }


    if h.flags&hashWriting == 0 {
        fatal("concurrent map writes")
    }
    h.flags &^= hashWritin
```  
  
   
  
（1）倘若 map 未初始化或者内部 key-value 对数量为 0，删除时不会报错，直接返回；  
```
if h == nil || h.count == 0 {
        return
}
```  
  
   
  
（2）倘若存在其他 goroutine 在进行写或删操作，抛出并发写的 fatal error；  
```
if h.flags&hashWriting != 0 {
    fatal("concurrent map writes")
}
```  
  
   
  
（3）通过 maptype.hasher() 方法求得 key 对应的 hash 值；  
```
 hash := t.hasher(key, uintptr(h.hash0))
```  
  
   
  
（4）通过异或位运算，将 map.flags 的第 3 个 bit 位置为 1，添加写标记；  
```
h.flags ^= hashWriting
```  
  
   
  
（5）找到当前 key 对应的桶索引 bucket；  
```
bucket := hash & bucketMask(h.B)
```  
  
   
  
（6）倘若发现当前 map 正处于扩容过程，则帮助其渐进扩容，具体内容在第 9 节中再作展开；  
```
   if h.growing() {
        growWork(t, h, bucket)
  }
```  
  
   
  
（7）从 map 的桶数组 buckets 出发，结合桶索引和桶容量大小，进行地址偏移，获得对应桶 b，并赋值给 bOrg；  
```
b := (*bmap)(add(h.buckets, bucket*uintptr(t.bucketsize)))
bOrig := b
```  
  
   
  
（8）取得 key 的高 8 位 tophash：  
```
top := tophash(hash)
```  
  
   
  
（9）开启两层 for 循环，外层沿着桶链表依次遍历，内层依次遍历桶内的 key-value 对.  
```
search:
    for ; b != nil; b = b.overflow(t) {
        for i := uintptr(0); i < bucketCnt; i++ {
            // ...
        }
    }
  
```  
  
   
  
（10）遍历时，倘若发现当前位置 tophash 值为 emptyRest，则直接结束遍历流程：  
```
   if b.tophash[i] != top {
        if b.tophash[i] == emptyRest {
             break search
         }
         continue
   }
          
```  
  
   
  
（11）倘若 key 不相等，则继续遍历：  
```
   k := add(unsafe.Pointer(b), dataOffset+i*uintptr(t.keysize))
   k2 := k
   if t.indirectkey() {
        k2 = *((*unsafe.Pointer)(k2))
    }
    if !t.key.equal(key, k2) {
        continue
    }
```  
  
   
  
（12）倘若 key 相等，则删除对应的 key-value 对，并且将当前位置的 tophash 置为 emptyOne：  
```
   if t.indirectkey() {
        *(*unsafe.Pointer)(k) = nil
    } else if t.key.ptrdata != 0 {
        memclrHasPointers(k, t.key.size)
    }
    e := add(unsafe.Pointer(b), dataOffset+bucketCnt*uintptr(t.keysize)+i*uintptr(t.elemsize))
    if t.indirectelem() {
        *(*unsafe.Pointer)(e) = nil
    } else if t.elem.ptrdata != 0 {
        memclrHasPointers(e, t.elem.size)
    } else {
        memclrNoHeapPointers(e, t.elem.size)
    }
    b.tophash[i] = emptyOne      
```  
  
   
  
（13）倘若当前位置不位于最后一个桶的最后一个位置，或者当前位置的后置位 tophash 不为 emptyRest，则无需向前遍历更新 tophash 标识，直接跳转到 notLast 位置即可；  
```
   if i == bucketCnt-1 {
        if b.overflow(t) != nil && b.overflow(t).tophash[0] != emptyRest {
            goto notLast
        }
    } else {
       if b.tophash[i+1] != emptyRest {
            goto notLast
        }
    }
```  
  
   
  
（14）向前遍历，将沿途的空位（ tophash 为 emptyOne ）的 tophash 都更新为 emptySet.  
```
   for {
                b.tophash[i] = emptyRest
                if i == 0 {
                    if b == bOrig {
                        break
                    }
                    c := b
                    for b = bOrig; b.overflow(t) != c; b = b.overflow(t) {
                    }
                    i = bucketCnt - 1
                } else {
                    i--
                }
                if b.tophash[i] != emptyOne {
                    break
                }
        }
          
```  
  
   
  
（15）倘若成功从 map 中删除了一组 key-value 对，则将 hmap 的计数器 count 值减 1. 倘若 map 中的元素全都被删除完了，会为 map 更换一个新的随机因子 hash0.  
```
   notLast:
        h.count--
        if h.count == 0 {
            h.hash0 = fastrand()
        }
        break search
      
```  
  
   
  
（16）收尾环节，再次校验是否有其他协程并发写，倘若有，则抛 fatal error. 将 hmap.flags 中的写标记抹去，然后退出方法.  
```
    if h.flags&hashWriting == 0 {
        fatal("concurrent map writes")
    }
    h.flags &^= hashWri
```  
  
   
# 8 遍历流程  
  
![](https://mmbiz.qpic.cn/mmbiz_png/3ic3aBqT2ibZuARxegbGpWRTtYV5T52c5xtldnPazf9FkWhjY67JHmaicXjG0E64JbzA4vslTRupKV3FnUTicPKDAg/640?wx_fmt=png "")  
  
map 的遍历流程首先会走进 runtime/map.go 的 mapiterinit() 方法当中，初始化用于遍历的迭代器 hiter；接着会调用 runtime/map.go 的 mapiternext() 方法开启遍历流程.  
  
   
## 8.1 迭代器数据结构  
```
type hiter struct {
    key         unsafe.Pointer 
    elem        unsafe.Pointer 
    t           *maptype
    h           *hmap
    buckets     unsafe.Pointer 
    bptr        *bmap         
    overflow    *[]*bmap      
    oldoverflow *[]*bmap      
    startBucket uintptr       
    offset      uint8         
    wrapped     bool         
    B           uint8
    i           uint8
    bucket      uintptr
    checkBucket uintptr
}
```  
  
hiter 是遍历 map 时用于存放临时数据的迭代器：  
  
（1）key：指向遍历得到 key 的指针；  
  
（2）value：指向遍历得到 value 的指针；  
  
（3）t：map 类型，包含了 key、value 类型大小等信息；  
  
（4）h：map 的指针；  
  
（5）buckets：map 的桶数组；  
  
（6）bptr：当前遍历到的桶；  
  
（7）overflow：新老桶数组对应的溢出桶；  
  
（8）startBucket：遍历起始位置的桶索引；  
  
（9）offset：遍历起始位置的 key-value 对索引；  
  
（10）wrapped：遍历是否穿越桶数组尾端回到头部了；  
  
（11）B：桶数组的长度指数；  
  
（12）i：当前遍历到的 key-value 对在桶中的索引；  
  
（13）bucket：当前遍历到的桶；  
  
（14）checkBucket：因为扩容流程的存在，需要额外检查的桶.  
  
   
## 8.2 mapiterinit  
  
map 遍历流程开始时，首先会走进 runtime/map.go 的 mapiterinit() 方法当中，此时会对创建 map 迭代器 hiter，并且通过取随机数的方式，决定遍历的起始桶号，以及起始 key-value 对索引号.  
  
   
  
![](https://mmbiz.qpic.cn/mmbiz_png/3ic3aBqT2ibZuARxegbGpWRTtYV5T52c5xBk4SR1Rc1oj3AHn95QftXDuuFqnJ4z4Ft00ViaqgTqy9hGs9WEIdV2Q/640?wx_fmt=png "")  
  
   
  
   
  
   
```
func mapiterinit(t *maptype, h *hmap, it *hiter) {
    it.t = t
    if h == nil || h.count == 0 {
        return
    }


    it.h = h


    it.B = h.B
    it.buckets = h.buckets
    if t.bucket.ptrdata == 0 {
        h.createOverflow()
        it.overflow = h.extra.overflow
        it.oldoverflow = h.extra.oldoverflow
    }


    // decide where to start
    var r uintptr
    r = uintptr(fastrand())
    it.startBucket = r & bucketMask(h.B)
    it.offset = uint8(r >> h.B & (bucketCnt - 1))


    // iterator state
    it.bucket = it.startBucket


    // Remember we have an iterator.
    // Can run concurrently with another mapiterinit().
    if old := h.flags; old&(iterator|oldIterator) != iterator|oldIterator {
        atomic.Or8(&h.flags, iterator|oldIterator)
    }


    mapiternext(
```  
  
   
  
（1）通过取随机数的方式，决定遍历时的起始桶，以及桶中起始 key-value 对的位置：  
```
   var r uintptr
    r = uintptr(fastrand())
    it.startBucket = r & bucketMask(h.B)
    it.offset = uint8(r >> h.B & (bucketCnt - 1))




    // iterator state
    it.bucket = it.startB
```  
  
   
  
（2）完成迭代器 hiter 中各项参数的初始化后，不如 mapiternext 方法开启遍历.  
  
   
## 8.2 mapiternext  
```
func mapiternext(it *hiter) {
    h := it.h
    if h.flags&hashWriting != 0 {
        fatal("concurrent map iteration and map write")
    }
    t := it.t
    bucket := it.bucket
    b := it.bptr
    i := it.i
    checkBucket := it.checkBucket


next:
    if b == nil {
        if bucket == it.startBucket && it.wrapped {
            it.key = nil
            it.elem = nil
            return
        }
        if h.growing() && it.B == h.B {
            oldbucket := bucket & it.h.oldbucketmask()
            b = (*bmap)(add(h.oldbuckets, oldbucket*uintptr(t.bucketsize)))
            if !evacuated(b) {
                checkBucket = bucket
            } else {
                b = (*bmap)(add(it.buckets, bucket*uintptr(t.bucketsize)))
                checkBucket = noCheck
            }
        } else {
            b = (*bmap)(add(it.buckets, bucket*uintptr(t.bucketsize)))
            checkBucket = noCheck
        }
        bucket++
        if bucket == bucketShift(it.B) {
            bucket = 0
            it.wrapped = true
        }
        i = 0
    }
    for ; i < bucketCnt; i++ {
        offi := (i + it.offset) & (bucketCnt - 1)
        if isEmpty(b.tophash[offi]) || b.tophash[offi] == evacuatedEmpty {
            continue
        }
        k := add(unsafe.Pointer(b), dataOffset+uintptr(offi)*uintptr(t.keysize))
        if t.indirectkey() {
            k = *((*unsafe.Pointer)(k))
        }
        e := add(unsafe.Pointer(b), dataOffset+bucketCnt*uintptr(t.keysize)+uintptr(offi)*uintptr(t.elemsize))
        if checkBucket != noCheck && !h.sameSizeGrow() {
                if checkBucket>>(it.B-1) != uintptr(b.tophash[offi]&1) {
                    continue
                }
            
        }
        if (b.tophash[offi] != evacuatedX && b.tophash[offi] != evacuatedY) ||
            !(t.reflexivekey() || t.key.equal(k, k)) {
            
            it.key = k
            if t.indirectelem() {
                e = *((*unsafe.Pointer)(e))
            }
            it.elem = e
        } else {
            rk, re := mapaccessK(t, h, k)
            if rk == nil {
                continue // key has been deleted
            }
            it.key = rk
            it.elem = re
        }
        it.bucket = bucket
        if it.bptr != b { // avoid unnecessary write barrier; see issue 14921
            it.bptr = b
        }
        it.i = i + 1
        it.checkBucket = checkBucket
        return
    }
    b = b.overflow(t)
    i = 0
    goto next
}
```  
  
   
  
（1）遍历时发现其他 goroutine 在并发写，直接抛出 fatal error：  
```
if h.flags&hashWriting != 0 {
    fatal("concurrent map iteration and map write")
}
```  
  
   
  
（2）开启最外圈的循环，依次遍历桶数组中的每个桶链表，通过 next 和 goto next 关键字实现循环代码块；  
```
next:
    if b == nil {
        // ...
        b = (*bmap)(add(it.buckets, bucket*uintptr(t.bucketsize)))
        // 
        bucket++
        if bucket == bucketShift(it.B) {
            bucket = 0
            it.wrapped = true
        }
        i = 0
    }
    // ...
    b = b.overflow(t)
    // ...
    goto next
}
```  
  
   
  
   
  
（3）倘若已经遍历完所有的桶，重新回到起始桶为止，则直接结束方法；  
```
 if bucket == it.startBucket && it.wrapped {
     it.key = nil
     it.elem = nil
     return
  }
```  
  
   
  
（4）倘若 map 处于扩容流程，取桶时兼容新老桶数组的逻辑. 倘若桶处于旧桶数组且未完成迁移，需要将 checkBucket 置为当前的桶号；  
```
 if h.growing() && it.B == h.B {
     oldbucket := bucket & it.h.oldbucketmask()
     b = (*bmap)(add(h.oldbuckets, oldbucket*uintptr(t.bucketsize)))
     if !evacuated(b) {
          checkBucket = bucket
     } else {
          b = (*bmap)(add(it.buckets, bucket*uintptr(t.bucketsize)))
          checkBucket = noCheck
     }
 } else {
     b = (*bmap)(add(it.buckets, bucket*uintptr(t.bucketsize)))
     checkBucket = noCheck
 }
```  
  
   
  
（5）遍历的桶号加 1，倘若来到桶数组末尾，则将桶号置为 0. 将 key-value 对的遍历索引 i 置为 0.  
```
bucket++
if bucket == bucketShift(it.B) {
     bucket = 0
     it.wrapped = true
}
i = 0
```  
  
   
  
（6）依次遍历各个桶中每个 key-value 对：  
```
    for ; i < bucketCnt; i++ {
        // ...
        return
    }
```  
  
   
  
（7）倘若遍历到的桶属于旧桶数组未迁移完成的桶，需要按照其在新桶中的顺序完成遍历. 比如，增量扩容流程中，旧桶中的 key-value 对最终应该被分散迁移到新桶数组的 x、y 两个区域，则此时遍历时，哪怕 key-value 对仍存留在旧桶中未完成迁移，遍历时也应该严格按照其在新桶数组中的顺序来执行.  
```
        if checkBucket != noCheck && !h.sameSizeGrow() {
            
                if checkBucket>>(it.B-1) != uintptr(b.tophash[offi]&1) {
                    continue
            }
        }
```  
  
   
  
（8）执行 mapaccessK 方法，基于读流程方法获取 key-value 对，通过迭代 hiter 的 key、value 指针进行接收，用于对用户的遍历操作进行响应：  
```
rk, re := mapaccessK(t, h, k)
if rk == nil {
      continue // key has been deleted
}
it.key = rk
it.elem = re
```  
  
   
  
   
# 9 扩容流程  
## 9.1 扩容类型  
  
![](https://mmbiz.qpic.cn/mmbiz_png/3ic3aBqT2ibZuARxegbGpWRTtYV5T52c5xIc21mmCq7ibWoBY9TkJwa0NjcE7edEVUlgKYLrsOlgbBCxLZiagYIjyA/640?wx_fmt=png "")  
  
   
  
map 的扩容类型分为两类，一类叫做增量扩容，一类叫做等量扩容.  
  
（1）增量扩容  
  
表现：扩容后，桶数组的长度增长为原长度的 2 倍；  
  
目的：降低每个桶中 key-value 对的数量，优化 map 操作的时间复杂度.  
  
   
  
（2）等量扩容  
  
表现：扩容后，桶数组的长度和之前保持一致；但是溢出桶的数量会下降.  
  
目的：提高桶主体结构的数据填充率，减少溢出桶数量，避免发生内存泄漏.  
  
   
## 9.2 何时扩容  
  
（1）只有 map 的写流程可能开启扩容模式；  
  
（2）写 map 新插入 key-value 对之前，会发起是否需要扩容的逻辑判断：  
```
func mapassign(t *maptype, h *hmap, key unsafe.Pointer) unsafe.Pointer {
    // ...
    
    if !h.growing() && (overLoadFactor(h.count+1, h.B) || tooManyOverflowBuckets(h.noverflow, h.B)) {
        hashGrow(t, h)
        goto again
    }


    // ...
}
```  
  
   
  
（3）根据 hmap 的 oldbuckets 是否空，可以判断 map 此前是否已开启扩容模式：  
```
func (h *hmap) growing() bool {
    return h.oldbuckets != nil
}
```  
  
   
  
（4）倘若此前未进入扩容模式，且 map 中 key-value 对的数量超过 8 个，且大于桶数组长度的 6.5 倍，则进入增量扩容：  
```
const(
   loadFactorNum = 13
   loadFactorDen = 2
   bucketCnt = 8
)


func overLoadFactor(count int, B uint8) bool {
    return count > bucketCnt && uintptr(count) > loadFactorNum*(bucketShift(B)/loadFactorDen)
}
```  
  
   
  
（5）倘若溢出桶的数量大于 2^B 个（即桶数组的长度；B 大于 15 时取15），则进入等量扩容：  
```
func tooManyOverflowBuckets(noverflow uint16, B uint8) bool {
    if B > 15 {
        B = 15
    }
    return noverflow >= uint16(1)<<(B&15)
}
```  
  
   
## 9.3 如何开启扩容模式  
  
开启扩容模式的方法位于 runtime/map.go 的 hashGrow 方法中：  
```
func hashGrow(t *maptype, h *hmap) {
    bigger := uint8(1)
    if !overLoadFactor(h.count+1, h.B) {
        bigger = 0
        h.flags |= sameSizeGrow
    }
    oldbuckets := h.buckets
    newbuckets, nextOverflow := makeBucketArray(t, h.B+bigger, nil)




    flags := h.flags &^ (iterator | oldIterator)
    if h.flags&iterator != 0 {
        flags |= oldIterator
    }
    // commit the grow (atomic wrt gc)
    h.B += bigger
    h.flags = flags
    h.oldbuckets = oldbuckets
    h.buckets = newbuckets
    h.nevacuate = 0
    h.noverflow = 0


    if h.extra != nil && h.extra.overflow != nil {
        // Promote current overflow buckets to the old generation.
        if h.extra.oldoverflow != nil {
            throw("oldoverflow is not nil")
        }
        h.extra.oldoverflow = h.extra.overflow
        h.extra.overflow = nil
    }
    if nextOverflow != nil {
        if h.extra == nil {
            h.extra = new(mapextra)
        }
        h.extra.nextOverflow = nextOverflow
    }
```  
  
   
  
（1）倘若是增量扩容，bigger 值取 1；倘若是等量扩容，bigger 值取 0，并将 hmap.flags 的第 4 个 bit 位置为 1，标识当前处于等量扩容流程.  
```
const sameSizeGrow = 8


bigger := uint8(1)
if !overLoadFactor(h.count+1, h.B) {
    bigger = 0
    h.flags |= sameSizeGrow
}
```  
  
   
  
（2）将原桶数组赋值给 oldBuckets，并创建新的桶数组和一批新的溢出桶.  
  
此处会通过变量 bigger，实现不同扩容模式下，新桶数组长度的区别处理.  
```
    oldbuckets := h.buckets
    newbuckets, nextOverflow := makeBucketArray(t, h.B+bigger, nil)
```  
  
   
  
（3）更新 hmap 的桶数组长度指数 B，flag 标识，并将新、老桶数组赋值给 hmap.oldBuckets 和 hmap.buckets；扩容迁移进度 hmap.nevacuate 标记为 0；新桶数组的溢出桶数量 hmap.noverflow 置为 0.  
```
    flags := h.flags &^ (iterator | oldIterator)
    if h.flags&iterator != 0 {
        flags |= oldIterator
    }
    // commit the grow (atomic wrt gc)
    h.B += bigger
    h.flags = flags
    h.oldbuckets = oldbuckets
    h.buckets = newbuckets
    h.nevacuate = 0
    h.noverflow = 0
```  
  
   
  
（4）将原本存量可用的溢出桶赋给 hmap.extra.oldoverflow；倘若存在下一个可用的溢出桶，赋给 hmap.extra.nextOverflow.  
```
   if h.extra != nil && h.extra.overflow != nil {
        h.extra.oldoverflow = h.extra.overflow
        h.extra.overflow = nil
    }
    if nextOverflow != nil {
        if h.extra == nil {
            h.extra = new(mapextra)
        }
        h.extra.nextOverflow = nextOverflow
  }
```  
  
   
## 9.4 扩容迁移规则  
  
![](https://mmbiz.qpic.cn/mmbiz_png/3ic3aBqT2ibZuARxegbGpWRTtYV5T52c5xGQ4uDFwF5OcI75CU0XqJorf8qgictnAicDqjjFnljJuvMnicJkx3RT1vg/640?wx_fmt=png "")  
  
（1）在等量扩容中，新桶数组长度与原桶数组相同；  
  
（2）key-value 对在新桶数组和老桶数组的中的索引号保持一致；  
  
（3）在增量扩容中，新桶数组长度为原桶数组的两倍；  
  
（4）把新桶数组中桶号对应于老桶数组的区域称为 x 区域，新扩展的区域称为 y 区域.  
  
（5）实际上，一个 key 属于哪个桶，取决于其 hash 值对桶数组长度取模得到的结果，因此依赖于其低位的 hash 值结果.；  
  
（6）在增量扩容流程中，新桶数组的长度会扩展一位，假定 key 原本从属的桶号为 i，则在新桶数组中从属的桶号只可能是 i （x 区域）或者 i + 老桶数组长度（y 区域）；  
  
（7）当 key 低位 hash 值向左扩展一位的 bit 位为 0，则应该迁往 x 区域的 i 位置；倘若该 bit 位为 1，应该迁往 y 区域对应的 i + 老桶数组长度的位置.  
  
   
## 9.5 渐进式扩容  
  
map 采用的是渐进扩容的方式，避免因为一次性的全量数据迁移引发性能抖动.  
  
当每次触发写、删操作时，会为处于扩容流程中的 map 完成两组桶的数据迁移：  
  
（1）一组桶是当前写、删操作所命中的桶；  
  
（2）另一组桶是，当前未迁移的桶中，索引最小的那个桶.  
```
func growWork(t *maptype, h *hmap, bucket uintptr) {
    // make sure we evacuate the oldbucket corresponding
    // to the bucket we're about to use
    evacuate(t, h, bucket&h.oldbucketmask())


    // evacuate one more oldbucket to make progress on growing
    if h.growing() {
        evacuate(t, h, h.nevacuate)
    }
}
```  
  
   
  
   
  
![](https://mmbiz.qpic.cn/mmbiz_png/3ic3aBqT2ibZuARxegbGpWRTtYV5T52c5xVwug95icdgSQMv2F6hYtjNLyQAvaL5O3xAKTiaD2NuicXia7A5ricbEuM7A/640?wx_fmt=png "")  
  
   
  
数据迁移的逻辑位于 runtime/map.go 的 evacuate 方法当中：  
```
func evacuate(t *maptype, h *hmap, oldbucket uintptr) {
    // 入参中，oldbucket 为当前要迁移的桶在旧桶数组中的索引
    // 获取到待迁移桶的内存地址 b
    b := (*bmap)(add(h.oldbuckets, oldbucket*uintptr(t.bucketsize)))
    // 获取到旧桶数组的容量 newbit
    newbit := h.noldbuckets()
    // evacuated 方法判断出桶 b 是否已经迁移过了，未迁移过，才进入此 if 分支进行迁移处理
    if !evacuated(b) {
        // 通过一个二元数组 xy 指向当前桶可能迁移到的目的桶
        // x = xy[0]，代表新桶数组中索引和旧桶数组一致的桶
        // y = xy[1]，代表新桶数组中，索引为原索引加上旧桶容量的桶，只在增量扩容中会使用到
        var xy [2]evacDst
        x := &xy[0]
        x.b = (*bmap)(add(h.buckets, oldbucket*uintptr(t.bucketsize)))
        x.k = add(unsafe.Pointer(x.b), dataOffset)
        x.e = add(x.k, bucketCnt*uintptr(t.keysize))


        // 只有进入增量扩容的分支，才需要对 y 进行初始化
        if !h.sameSizeGrow() {
            // Only calculate y pointers if we're growing bigger.
            // Otherwise GC can see bad pointers.
            y := &xy[1]
            y.b = (*bmap)(add(h.buckets, (oldbucket+newbit)*uintptr(t.bucketsize)))
            y.k = add(unsafe.Pointer(y.b), dataOffset)
            y.e = add(y.k, bucketCnt*uintptr(t.keysize))
        }


        // 外层 for 循环，遍历桶 b 和对应的溢出桶
        for ; b != nil; b = b.overflow(t) {
            // k,e 分别记录遍历桶时，当前的 key 和 value 的指针
            k := add(unsafe.Pointer(b), dataOffset)
            e := add(k, bucketCnt*uintptr(t.keysize))
            // 遍历桶内的 key-value 对
            for i := 0; i < bucketCnt; i, k, e = i+1, add(k, uintptr(t.keysize)), add(e, uintptr(t.elemsize)) {
                top := b.tophash[i]
                if isEmpty(top) {
                    b.tophash[i] = evacuatedEmpty
                    continue
                }
                if top < minTopHash {
                    throw("bad map state")
                }
                k2 := k
                if t.indirectkey() {
                    k2 = *((*unsafe.Pointer)(k2))
                }
                var useY uint8
                if !h.sameSizeGrow() {
                    // Compute hash to make our evacuation decision (whether we need
                    // to send this key/elem to bucket x or bucket y).
                    hash := t.hasher(k2, uintptr(h.hash0))
                    if hash&newbit != 0 {
                       useY = 1
                    }
                }
                b.tophash[i] = evacuatedX + useY // evacuatedX + 1 == evacuatedY
                dst := &xy[useY]                 // evacuation destination
                if dst.i == bucketCnt {
                    dst.b = h.newoverflow(t, dst.b)
                    dst.i = 0
                    dst.k = add(unsafe.Pointer(dst.b), dataOffset)
                    dst.e = add(dst.k, bucketCnt*uintptr(t.keysize))
                }
                dst.b.tophash[dst.i&(bucketCnt-1)] = top // mask dst.i as an optimization, to avoid a bounds check
                if t.indirectkey() {
                    *(*unsafe.Pointer)(dst.k) = k2 // copy pointer
                } else {
                    typedmemmove(t.key, dst.k, k) // copy elem
                }
                if t.indirectelem() {
                    *(*unsafe.Pointer)(dst.e) = *(*unsafe.Pointer)(e)
                } else {
                    typedmemmove(t.elem, dst.e, e)
                }
                dst.i++
                dst.k = add(dst.k, uintptr(t.keysize))
                dst.e = add(dst.e, uintptr(t.elemsize))
            }
        }
        // Unlink the overflow buckets & clear key/elem to help GC.
        if h.flags&oldIterator == 0 && t.bucket.ptrdata != 0 {
            b := add(h.oldbuckets, oldbucket*uintptr(t.bucketsize))
            // Preserve b.tophash because the evacuation
            // state is maintained there.
            ptr := add(b, dataOffset)
            n := uintptr(t.bucketsize) - dataOffset
            memclrHasPointers(ptr, n)
        }
    }


    if oldbucket == h.nevacuate {
        advanceEvacuationMark(h, t, newbit)
    }
}


func (h *hmap) noldbuckets() uintptr {
    oldB := h.B
    if !h.sameSizeGrow() {
        oldB--
    }
    return bucketShift(oldB)
```  
  
（1）从老桶数组中获取到待迁移的桶 b；  
```
b := (*bmap)(add(h.oldbuckets, oldbucket*uintptr(t.bucketsize)))
```  
  
（2）获取到老桶数组的长度 newbit；  
```
newbit := h.noldbuckets()
```  
  
（3）倘若当前桶已经完成了迁移，则无需处理；  
  
（4）创建一个二元数组 xy，分别承载 x 区域和 y 区域（含义定义见 9.4 小节）中的新桶位置，用于接受来自老桶数组的迁移数组；只有在增量扩容的流程中，才存在 y 区域，因此才需要对 xy 中的 y 进行定义；  
```
var xy [2]evacDst
x := &xy[0]
x.b = (*bmap)(add(h.buckets, oldbucket*uintptr(t.bucketsize)))
x.k = add(unsafe.Pointer(x.b), dataOffset)
x.e = add(x.k, bucketCnt*uintptr(t.keysize))


if !h.sameSizeGrow() {
    y := &xy[1]
    y.b = (*bmap)(add(h.buckets, (oldbucket+newbit)*uintptr(t.bucketsize)))
    y.k = add(unsafe.Pointer(y.b), dataOffset)
    y.e = add(y.k, bucketCnt*uintptr(t.keysize))
}
```  
  
   
  
（5）开启两层 for 循环，外层遍历桶链表，内层遍历每个桶中的 key-value 对：  
```
    for ; b != nil; b = b.overflow(t) {
        k := add(unsafe.Pointer(b), dataOffset)
        e := add(k, bucketCnt*uintptr(t.keysize))
        for i := 0; i < bucketCnt; i, k, e = i+1, add(k, uintptr(t.keysize)), add(e, uintptr(t.elemsize)) {
           // ...
        }
    }
       
```  
  
   
  
（6）取每个位置的 tophash 值进行判断，倘若当前是个空位，则将当前位置 tophash 值置为 evacuatedEmpty，开始遍历下一个位置：  
```
 top := b.tophash[i]
 if isEmpty(top) {
      b.tophash[i] = evacuatedEmpty
      continue
 }
```  
  
   
  
（7）基于 9.4 的规则，寻找到迁移的目的桶；  
```
  const evacuatedX = 2
  const evacuatedY = 3  


  k2 := k
  var useY uint8
  if !h.sameSizeGrow() {       
       hash := t.hasher(k2, uintptr(h.hash0))
       if hash&newbit != 0 {
            useY = 1
       }
  }
  b.tophash[i] = evacuatedX + useY // evacuatedX + 1 == evacuatedY
  dst := &xy[useY]
```  
  
   
  
其中目的桶的类型定义如下：  
```
type evacDst struct {
    b *bmap          // current destination bucket
    i int            // key/elem index into b
    k unsafe.Pointer // pointer to current key storage
    e unsafe.Pointer // pointer to current elem storage
}
```  
  
I evacDst.b：目的地的所在桶；  
  
II evacDst.i：即将入桶的 key-value 对在桶中的索引；  
  
III evacDst.k：入桶 key 的存储指针；  
  
IV evacDst.e：入桶 value 的存储指针.  
  
   
  
（8）将 key-value 对迁移到目的桶中，并且更新目的桶结构内几个指针的指向：  
```
  if dst.i == bucketCnt {
       dst.b = h.newoverflow(t, dst.b)
       dst.i = 0
       dst.k = add(unsafe.Pointer(dst.b), dataOffset)
       dst.e = add(dst.k, bucketCnt*uintptr(t.keysize))
  }
  dst.b.tophash[dst.i&(bucketCnt-1)] = top // mask dst.i as an optimization, to avoid a bounds check
  if t.indirectkey() {
       *(*unsafe.Pointer)(dst.k) = k2 // copy pointer
  } else {
       typedmemmove(t.key, dst.k, k) // copy elem
  }
  if t.indirectelem() {
       *(*unsafe.Pointer)(dst.e) = *(*unsafe.Pointer)(e)
  } else {
       typedmemmove(t.elem, dst.e, e)
  }
  dst.i++
  dst.k = add(dst.k, uintptr(t.keysize))
  dst.e = add(dst.e, uintptr(t.elemsize
```  
  
   
  
（9）倘若当前迁移的桶是旧桶数组未迁移的桶中索引最小的一个，则 hmap.nevacuate 累加 1.  
  
倘若已经迁移完所有的旧桶，则会确保 hmap.flags 中，等量扩容的标识位被置为 0.  
```
  if oldbucket == h.nevacuate {
      advanceEvacuationMark(h, t, newbit)
  }
```  
  
   
```
func advanceEvacuationMark(h *hmap, t *maptype, newbit uintptr) {
    h.nevacuate++
    // ...
    if h.nevacuate == newbit { // newbit == # of oldbuckets
        h.oldbuckets = nil
        if h.extra != nil {
            h.extra.oldoverflow = nil
        }
        h.flags &^= sameSizeGrow
    }
}
```  
  
# 10 Go 1.24+ Swiss Table
  
![](https://mmbiz.qpic.cn/mmbiz_jpg/YxZZJFehFua28icasKlhpYUu0iafvABFxwILd96yvZ6h8Sf6TbiaAdCXibt9AeohIDtpHPATGV9LobdDYGjLTgajcw/640?wx_fmt=jpeg "")  
在本文中，我们将探讨Go语言新的Swiss Tables实现如何帮助减少大型内存映射的内存使用，展示我们如何分析和衡量这一变化，并分享结构体层面的优化，这些优化带来了更大的全舰队范围节省。  
为了更好地理解在高流量环境下内存使用量下降的原因，我们开始查看给定服务的实时堆。更仔细地比较了前后，我们发现：  
![我们在一张名为 shardRoutingCache 的映射上节省了大约 500 MiB 的实时堆使用量，该映射位于 ShardRouter 包中。](https://mmbiz.qpic.cn/mmbiz_jpg/YxZZJFehFua28icasKlhpYUu0iafvABFxwbSXuOM0FsBzu7yJxibfJRibGLMKKBl5OvXcC7GaT3c2hE7YYIlt00CsA/640?from=appmsg "")  
我们在一张名为shardRoutingCache的映射上节省了大约**500 MiB**的实时堆使用量，该映射位于ShardRouter包中。如果考虑到默认设置为100的Go垃圾回收器（GOGC），这将使内存使用量减少**1 GiB（即500 x 2）**。  
当我们计入第一部分中描述的mallocgc问题导致的约400 MiB RSS增长时，我们仍然看到**净减少600 MiB的内存使用量**！  
这究竟是为什么呢？首先，让我们深入了解shardRoutingCache映射及其填充方式。  
我们的一些Go数据处理服务使用ShardRouter包。顾名思义，该包根据路由键确定传入数据的目标分片。这是通过在启动时查询数据库，并使用响应来填充shardRoutingCache映射来实现的。  
该映射的布局如下：  
### 估算每个条目的内存占用  
为了更好地估算内存减少量，我们来计算每个键值对的大小。在64位架构上，键的大小为**16字节**（字符串头大小）。每个值的大小将对应：  
- shardID int32 占 **4字节**  
- shardType int 占 **8字节**  
- routingKey string 头信息占 **16字节**  
- lastModifiedTimestamp 指针占 **8字节**  
我们稍后会讨论routingKey字符串本身的长度以及lastModifiedTimestamp指向的time.Time结构体的大小（暂不剧透！）。目前，我们假设**字符串为空，指针为nil**。  
这意味着每个值分配了：(4+8+16+8) = **36字节**，加上填充[1]后为**40字节**。总的来说，每个键值对需要**56字节**。  
大多数分配发生在服务启动时查询数据库期间。这意味着，在服务生命周期内，此映射很少插入新数据。稍后我们将看到这如何影响映射的大小。  
现在，让我们回顾一下Go 1.23与Go 1.24中映射的工作方式，以及这如何影响shardRoutingCache映射的大小。  
## Go 1.23 基于桶的 Map 实现解析  
### 桶结构与布局  
Go 1.23 中 Map 的运行时实现基于哈希表，并以桶数组的形式组织。在 Go 的实现中，**桶的数量始终是 2 的幂**（2n），每个桶包含 **8 个槽位**用于存储 Map 的键值对。我们通过一个包含 **2 个桶的 Map** 示例来直观了解：  
![每个桶包含八个槽位，用于存储 Map 的键值对。](https://mmbiz.qpic.cn/mmbiz_jpg/YxZZJFehFua28icasKlhpYUu0iafvABFxwlzfbajzw4JYojvwoa71g9PA6ib5S5KiaC2icLhffXwsyv4I1Ugvic3R3gA/640?from=appmsg "")  
插入新的键值对时，元素放置的桶由哈希函数 hash(key) 确定。然后，需要扫描桶中所有现有元素，以判断键是否与 Map 中现有键匹配：  
- **如果匹配**，则更新该键值对。  
- **否则**，将元素插入第一个空槽位。  
![插入新的键值对时，元素放置的桶由哈希函数 hash(key) 确定。](https://mmbiz.qpic.cn/mmbiz_jpg/YxZZJFehFua28icasKlhpYUu0iafvABFxwkzmS6ic6ptIjDrPX2CBpxrW8H4kSIxGcr66Pic40AQYZlOMDljBqkVJA/640?from=appmsg "")  
类似地，从 Map 读取元素时，也必须扫描桶中所有现有元素。这种对桶中所有元素的读写扫描操作通常是 Map 操作 CPU 开销的重要组成部分。  
当一个桶已满——但其他桶仍有大量空间时——新的键值对会被添加到与原始桶链接的溢出桶中。在每次读/写操作时，也会扫描溢出桶，以确定是插入新元素还是更新现有元素：  
![每次写入时，也会扫描溢出桶，以确定是插入新元素还是更新现有元素。](https://mmbiz.qpic.cn/mmbiz_jpg/YxZZJFehFua28icasKlhpYUu0iafvABFxwYABy6SWuaB1RVmFzibuNpzibaSibpwuiaicR7q6mkgbU87tt3vS0xk0CfzA/640?from=appmsg "")  
当一个溢出桶已满——但其他桶仍有大量空间时——可以添加一个新的溢出桶并与前一个溢出桶链接，以此类推。  
### Map 扩容与负载因子  
最后，我们讨论 Map 的扩容及其对桶数量的影响。初始桶的数量由 Map 的初始化方式决定：  
对于每个桶，**负载因子**是桶中元素数量与桶大小之比。在上面的示例中，桶 0 的负载因子为 **8/8**，桶 1 的负载因子为 **1/8**。  
随着 Map 的增长，Go 会跟踪所有非溢出桶的**平均负载因子**。当平均负载因子严格高于 **13/16 (或 6.5/8)** 时，我们需要将 Map 重新分配到一个桶数量翻倍的新 Map。通常，下一次插入会创建一个新的桶数组——大小是原来的两倍——理论上，也应该将旧桶数组的内容复制到新数组。  
由于 Go 经常用于对延迟敏感的服务器，我们不希望内置操作对延迟造成任意大的影响。因此，Go 在 1.23 之前不会在单次插入时复制整个底层 Map 到新 Map，而是会同时保留两个数组：  
![Go 在 1.23 之前不会在单次插入时复制整个底层 Map 到新 Map，而是会同时保留两个 Map。](https://mmbiz.qpic.cn/mmbiz_jpg/YxZZJFehFua28icasKlhpYUu0iafvABFxwqxicUkcPOd3icrUR7HnhRx0SzQWkplRfiahTGZ9ialyCtC48GzS2mb1zEA/640?from=appmsg "")  
每次对 Map 进行新的写入时，Go 会增量地将项目从旧桶移动到新桶：  
![高负载因子意味着平均每个桶将包含更多的键值对。图示为两个旧桶和四个新桶。](https://mmbiz.qpic.cn/mmbiz_jpg/YxZZJFehFua28icasKlhpYUu0iafvABFxwibmlicEXpAibDLlyPCFoHwfAbvsYj3uOITxzjRI90HQp0oPVtw5aR8tUQ/640?from=appmsg "")  
**关于负载因子**: 高负载因子意味着平均每个桶将包含更多的键值对。因此，插入元素时，我们需要扫描每个桶中更多的键，以判断是更新现有元素还是将元素插入空槽位。读取值时也同样适用。另一方面，低负载因子意味着大部分桶处于空闲状态，导致内存浪费。  
### 估算map内存占用  
现在我们已掌握估算Go 1.23中shardRoutingCache map大小所需的大部分信息。我们有一个自定义指标，显示map中存储的元素数量：  
![map中的元素数量：3500000。](https://mmbiz.qpic.cn/mmbiz_jpg/YxZZJFehFua28icasKlhpYUu0iafvABFxwBicmvXbSSb332libsul9AZnBeEpk6ibqjZ74hSSVcWsFFfmUxCRlR03Dg/640?from=appmsg "")  
对于约3,500,000个元素，最大平均负载因子为**13/16**，我们至少需要：  
- **所需桶数** = 3,500,000 / (8 x 13/16) ≈ **538,462个桶**  
- 大于538,462的最小2次幂是2^20 = **1,048,576个桶**  
然而，由于538,462接近524,288 (2^19)，且shardRoutingCache map写入频率较低，**旧的桶很可能仍处于已分配状态**——我们仍处于从旧map向新大map过渡的阶段。  
这意味着shardRoutingCache分配了2^20（新桶）+ 2^19（旧桶），即**1,572,864个桶**。  
每个桶结构包含：  
- 一个**溢出桶指针**（64位架构上为8字节）  
- 一个**8字节数组**（内部使用）  
- **8个键值对**，每个56字节：56 × 8 = **448字节**  
这意味着**每个桶占用464字节**内存。  
因此，对于Go 1.23，桶数组占用的总内存为：  
- **1,572,864个桶** × **464字节/桶** = 729,808,896字节 ≈ **696 MiB**。  
但这仅是主桶数组的内存占用。我们还需要考虑**溢出桶**。对于分布良好的哈希函数，溢出桶的数量应该相对较少。  
Go map实现会根据桶的数量预分配溢出桶 (2^n-4个溢出桶)。对于2^20个桶，这意味着大约**2^16 = 65,536个溢出桶**可能被预分配，额外增加**65,536个溢出桶** × **464字节/桶**——总计约**30.4 MiB**。  
总的来说，map的估计总内存占用为：  
- **主桶数组（包括旧桶）≈ 696 MiB**  
- **预分配溢出桶 ≈ 30.4 MiB**  
- **总计 ≈ 726.4 MiB**  
这与实时堆剖析中的观察结果相符，即Go 1.23中shardRoutingCache map的实时堆使用量约为**930 MiB**：其中**730 MiB**用于map本身，**200 MiB**用于为路由键分配底层字符串。  
## Swiss Tables与可扩展哈希的变革  
Go 1.24引入了基于Swiss Tables[2]和可扩展哈希[3]的全新map实现。在Swiss Tables中，数据以组的形式存储：每组包含**8个槽位**用于存储键值对，以及一个**64位控制字**（8字节）。Swiss Table中的组数量始终是2的幂。  
我们来看一个包含两个组的表的例子：  
![Number of groups in a Swiss Table is always a power of 2.](https://mmbiz.qpic.cn/mmbiz_jpg/YxZZJFehFua28icasKlhpYUu0iafvABFxwY0d50gOl8LDCgX2bxqaI2zVSkobq63CibuiaMiagYN7RKImKpb7FDfVag/640?from=appmsg "")  
控制字中的每个字节都与一个槽位关联。第一个位指示该槽位是**空闲**、**已删除**还是**使用中**。如果槽位在使用中，剩余的7位存储键哈希的低位。  
### Swiss Tables插入操作  
我们来看看如何将一个新的键值对插入到这个2组Swiss Table中。首先，计算键k1的64位哈希hash(k1)，并将其分成两部分：前57位称为h1，后7位称为h2。  
通过计算h1 mod 2（因为有2个组）来确定使用哪个组。如果h1 mod 2 == 0，我们将尝试把键值对存储在组0中：  
![If h1 mod 2 == 0, we’ll try to store the key–value pair in group 0.](https://mmbiz.qpic.cn/mmbiz_jpg/YxZZJFehFua28icasKlhpYUu0iafvABFxwKbFkMZtMt5kekxG6CNPYuOFGLRKlbYoZeHvQdCdkkBdOyMH8yuFgrQ/640?from=appmsg "")  
在存储该键值对之前，我们检查组0中是否已存在具有相同键的键值对。如果存在，我们需要更新现有键值对；否则，将新元素插入到第一个空闲槽位中。  
这正是Swiss Tables的亮点：以前，要完成这项操作，我们必须线性探测桶中的所有键值对。  
在Swiss Tables中，**控制字让我们能更高效地完成此操作**。由于每个字节都包含该槽位哈希的低7位（h2），我们可以首先将要插入的键值对的h2与控制字每个字节的低7位进行比较。  
此操作受**单指令多数据** (SIMD)[4]硬件支持，其中该比较通过**单个CPU指令**在组中所有8个槽位上并行完成。当没有专门的SIMD硬件时，这通过标准的**算术和位操作**实现。  
**注意**：截至Go 1.24.2，arm64架构尚不支持基于SIMD的map操作。您可以关注（并点赞）跟踪非amd64架构实现进度的GitHub issue[5]。  
### 处理满载组  
当组中所有槽位都已满时会发生什么？此前，在Go 1.23中，我们不得不创建**溢出桶**。使用Swiss Tables，我们将键值对存储在下一个有可用槽位的组中。由于探测速度很快，运行时可以检查额外的组以确定元素是否已存在。探测序列在到达第一个**空闲（非已删除）** 槽位的组时停止：  
![Inserting k9, v9 into the Swiss Table.](https://mmbiz.qpic.cn/mmbiz_jpg/YxZZJFehFua28icasKlhpYUu0iafvABFxwery4kHxBRAAwIhX4FhxtoG6Fc4icMVXk1RkyCFYHcv0iaEC8xZCSzQ8A/640?from=appmsg "")  
因此，这种快速探测技术使我们能够消除**溢出桶**的概念。  
### 分组负载因子与映射增长  
现在我们来看看Swiss Tables中映射增长的工作原理。与之前一样，每个分组的**负载因子**定义为分组中的元素数量除以其容量。在上述示例中，分组0的负载因子为**8/8**，分组1的负载因子为**2/8**。  
由于控制字使得探测速度大大加快，Swiss Tables默认使用**更高的最大负载因子（7/8）**，这会减少内存使用。  
当平均负载因子严格高于7/8时，我们需要将映射重新分配到一个桶数量翻倍的新映射。通常，下一次插入操作将导致表格分裂。  
但是，对于Go 1.23实现中提到的，如何限制对延迟敏感服务器的尾部延迟呢？如果映射包含数千个分组，单次插入操作将承担移动和重新哈希所有现有元素的开销，这可能耗费大量时间：  
![当插入(k,v)时，负载因子严格高于7/8时，表格分裂操作的示意图。](https://mmbiz.qpic.cn/mmbiz_jpg/YxZZJFehFua28icasKlhpYUu0iafvABFxwAqLYWiaCdwHxVlib0UcmzKt7V5yePmIgzIM4kVHlz2bz4Ugiap9S3GI0A/640?from=appmsg "")  
Go 1.24通过限制单个Swiss Table中可以存储的分组数量来解决这个问题。单个表格最多可以存储**128个分组（1024个槽位）**。  
如果我们想存储超过1024个元素怎么办？这就是**可扩展哈希**发挥作用的地方。  
映射不再由**单个Swiss Table**实现，而是由**一个或多个独立Swiss Tables的目录**组成。使用**可扩展哈希**，密钥哈希中可变数量的高位用于确定密钥属于哪个表格：  
![每个映射是一个或多个独立Swiss Tables的目录。](https://mmbiz.qpic.cn/mmbiz_jpg/YxZZJFehFua28icasKlhpYUu0iafvABFxw3rHasCIGPklHWgiapy8700TZKibu4IiafX4jFYZvr1vyY0qDXt892DGFQ/640?from=appmsg "")  
可扩展哈希实现了两件事：  
- **有界分组复制**：通过限制单个Swiss Table的大小，添加新分组时需要复制的元素数量受到限制。  
- **独立表格分裂**：当一个表格达到128个分组时，它会分裂成两个128个分组的Swiss Table。这是最昂贵的操作，但它是受限的，并且每个表格独立进行。  
因此，对于非常大的表格，**Go 1.24的表格分裂方法**比Go 1.23的**内存效率更高**，因为Go 1.23在增量迁移期间会将旧桶保留在内存中。  
回顾与Go 1.23相比的内存节省：  
- **更高负载因子**：Swiss Tables支持更高的负载因子**87.5%**（Go 1.23为81.25%），所需总槽位更少。  
- **消除溢出桶**：Swiss Table消除了对溢出存储的需求。它们还消除了溢出桶指针，抵消了控制字的额外占用空间。  
- **更高效的增长**：与Go 1.23在增量迁移期间将旧桶保留在内存中不同，Go 1.24的表格分裂方法内存效率更高。  
### 估算映射内存使用量  
现在，我们将所学知识应用于估算Go 1.24上shardRoutingCache映射的大小。  
对于**3,500,000个元素**，最大平均负载因子为**7/8**，我们至少需要：  
- **所需分组数** = 3,500,000 / (8 x 7/8) ≈ **500,000个分组**  
- **所需表格数** = 500,000（分组）/ 128（每表格分组数）≈ **3900个表格**  
由于表格独立增长，一个目录可以包含任意数量的表格，而不仅仅是2的幂次方。  
每个表格存储**128个分组**。每个分组有：  
- 一个**控制字：8字节**  
- **8对键值对，每对56字节**：56 × 8 = **448字节**  
这意味着每个表格使用**(448 + 8)字节/分组 x 128分组 ≈ 58,368字节**。  
因此，对于**Go 1.24**，Swiss Tables使用的总内存为：**3,900个表格 × 58,368字节/表格 = 227,635,200字节 ≈ 217 MiB**。（在**Go 1.23**中，映射的大小约为**726.4 MiB**。）  
这与我们之前在实时堆剖析中观察到的结果一致：切换到**Go 1.24**为shardRoutingCache映射节省了大约**500 MiB的实时堆使用量**——或在考虑GOGC[6]时大约**1GiB的RSS**。  
## 低流量环境下未见同等收益的原因  
首先，我们来看低流量环境下映射中的元素数量：  
![低流量环境下映射中的元素数量：550000。](https://mmbiz.qpic.cn/mmbiz_jpg/YxZZJFehFua28icasKlhpYUu0iafvABFxwECNrdTS94wJcspFrm3rSsibYiaU2o9EdyU4XZyRrHhYBfAfdZHg6HKlw/640?from=appmsg "")  
考虑到这一点，我们应用相同的公式。  
### Go 1.23 中基于桶的哈希表  
对于 **550,000 个元素**，最大平均负载因子为 **13/16**，我们至少需要：  
- **所需桶数** = 550,000 / (8 x 13/16) ≈ **84,615 个桶**  
- 大于 84,615 的最小 2 的幂是 2^17 = **131,072 个桶**  
由于 84,615 远大于 2^16 (**65,536**)，我们可以预期最近一次扩容后的旧桶将被释放。  
这也对应着 2^13 **预分配的溢出桶**，所以桶的总数是：  
- **2^18 + 2^14 = 139,264 个桶**  
因此，对于 Go 1.23，桶数组占用的总内存为：  
- **139,264 个桶 × 464 字节/桶 = 64,618,496 字节 ≈ 62 MiB**  
### Go 1.24 中使用 Swiss Tables  
对于相同的 **550,000 个元素**，最大平均负载因子为 **7/8**，我们需要：  
- **所需组数** = 550,000 / (8 × 7/8) ≈ **78,571 组**  
- **所需表数** = 78,571 (组) / 128 (组/表) ≈ **614 张表**  
每张表使用：  
- **(448 + 8) 字节/组 × 128 组 ≈ 58,368 字节**  
所以 Swiss Tables 占用的总内存为：  
- **614 张表 × 58,368 字节/桶 = 35,838,144 字节 ≈ 34 MiB**  
实时堆使用量仍有大约 **~28 MiB 的减少**。然而，这一节省量比我们观察到的 mallocgc 回归导致的 **200-300 MiB RSS 增加**要**小一个数量级**。因此，在低流量环境中，总体内存使用量仍然增加，这与我们的观察结果一致。  
但仍有优化内存使用的机会。  
## 我们如何进一步减少映射内存使用  
回顾我们之前查看 shardRoutingCache 映射时：  
最初，我们假设 RoutingKey 字符串为空，并且 LastModified 指针为 nil。然而，我们所有的计算都合理，并提供了一个很好的内存近似值。这是为什么呢？  
在审查代码后，我们发现 shardRoutingCache 映射中的 RoutingKey 和 LastModified 属性从未被填充。尽管 Response 结构在其他地方使用了这些已设置的字段，但在此特定用例中它们保持未设置状态。  
顺便一提，我们还注意到 ShardType 字段是一个 int64 枚举——但它只有三个可能的值。这意味着我们可以直接使用 uint8，仍然有足够的空间容纳多达 255 个枚举值。  
考虑到这个映射可能会变得非常大，我们认为值得优化。我们起草了一个 PR，做了两件事：  
1. 将 ShardType 字段从 int (8 字节) 切换到 uint8 (1 字节)，允许我们存储多达 255 个值。  
2. 引入了一个新类型 cachedResponse，它只包含 ShardID 和 ShardType——这样我们就不再存储空字符串和 nil 指针。  
这将单个键值对的大小从 56 字节减少到：  
- **16 字节** 用于键指纹（无变化）  
- **4 字节** 用于 ShardID  
- **1 字节** 用于 ShardType (**+ 3 字节用于填充**)  
这使得每个键值对的大小为 **24 字节（带填充）**。  
在我们的高流量环境中，这大致将映射的大小从 **217 MiB** 减少到 **93 MiB**。  
如果我们将 GOGC 考虑在内[6]，这大致意味着使用该组件的所有数据处理服务，每个 Pod 的 RSS **减少约 250 MiB**。  
我们通过实时堆分析确认了内存节省——现在是时候考虑操作影响了。  
## 如何实现成本缩减？  
此次映射优化已部署到所有数据处理服务，目前我们可考虑两种途径实现成本缩减。  
**方案一：降低容器的Kubernetes内存限制。** 这将允许集群上的其他应用使用我们为每个Pod释放的内存。  
![图表显示数据处理服务在所有环境中RAM减少了200TiB。](https://mmbiz.qpic.cn/mmbiz_jpg/YxZZJFehFua28icasKlhpYUu0iafvABFxwOPEzOicfJqXtXeo5vSo6jMOE4CFUteJvg0v3MeenhfpeAiaLa3RiaYyTA/640?from=appmsg "")  
**方案二：使用GOMEMLIMIT进行内存换取CPU。** 如果工作负载是CPU密集型的，设置GOMEMLIMIT[7]可以将在内存上节省的资源用于CPU。CPU的节省能让我们缩减Pod的数量。  
对于一些已设置GOMEMLIMIT的工作负载，我们观察到平均CPU使用率略有下降：  
![高流量环境下另一个服务的平均CPU使用率（右侧绿色条表示4月初的新版本）。](https://mmbiz.qpic.cn/mmbiz_jpg/YxZZJFehFua28icasKlhpYUu0iafvABFxw6syXOKfibGDSc3xksaGcYGgdAW8oTgM4AXggSTlLfiaFjaqNn6XlAibUw/640?from=appmsg "")  
## Go 1.24在生产环境：收获与经验  
此次调查揭示了Go应用内存优化方面的几点重要见解：  
- **通过与广泛的Go社区协作，我们发现、诊断并协助修复了Go 1.24中引入的一个微妙但影响深远的内存回归问题。** 尽管该问题在Go的内部堆指标中不可见，但它影响了许多工作负载的物理内存使用量（RSS）。  
- **每个新的语言版本都会带来优化，但也伴随着回归的风险，可能对生产系统造成显著影响。** 及时更新Go版本不仅能让我们利用Swiss Tables等性能改进，也能帮助我们尽早发现和解决问题，避免其在生产环境中大规模爆发。  
- **运行时指标和实时堆分析对我们的调查至关重要。** 它们帮助我们形成了准确的假设，追踪了RSS与Go管理内存之间的差异，并与Go团队进行了有效沟通。如果没有详细的指标和高效的分析能力，这类微妙的问题可能无法被发现或被误诊。  
- **Go 1.24中引入的Swiss Tables相比Go 1.23中基于桶的哈希表，显著节省了内存——尤其对于大型映射。** 在我们的高流量环境中，这使得映射内存使用量**减少了约70%**。  
- **除了运行时层面的改进，我们自身的数据结构优化也产生了实际影响。** 通过精炼Response结构体以消除未使用的字段并使用适当大小的类型，我们进一步降低了内存消耗。  
![](https://mmbiz.qpic.cn/mmbiz_gif/YxZZJFehFuaic6PZtOsB7GbKdNaWJCl9BaL81ghibspxexsWDeJq13kicOrGtNU5kYJeS7DBicDz8LhaE3MeEd0S9Q/640?wx_fmt=gif&from=appmsg "")  
1. 
[从头实现一个 TSDB 时间序列数据库 - 性能优化](http://mp.weixin.qq.com/s?__biz=MjM5NzUwODgyNA==&mid=2247484099&idx=1&sn=277656da2a05e043d004c3e4e302e2d0&chksm=a6d9a17491ae28628df2b6027bb0731f4a768c56d2f22e22cea2537de7a6037127f1860fcce5&scene=21#wechat_redirect)  
2. 
[Go 语言下的批处理式快速洗牌算法](http://mp.weixin.qq.com/s?__biz=MjM5NzUwODgyNA==&mid=2247489057&idx=1&sn=37cbc4d32cef84d1436fd5696568e1d4&chksm=a6d9b59691ae3c80521a6bcb6b04ce98bdf4bc74ab3e2a9101cb75eb25577cebc4fd7daeb090&scene=21#wechat_redirect)  
3. 
[使用 Rust、Bert 和 Qdrant 进行语义搜索](http://mp.weixin.qq.com/s?__biz=MjM5NzUwODgyNA==&mid=2247488564&idx=1&sn=d9ccaff022490ac93e9acf42f47aa069&chksm=a6d9b78391ae3e95e8fa4dedb45a2800273f855f7cf1c8b8ebe5215dcc15420511654c9027c2&scene=21#wechat_redirect)  
4. 
[Go Protobuf：不透明 API](http://mp.weixin.qq.com/s?__biz=MjM5NzUwODgyNA==&mid=2247488125&idx=1&sn=9f05a7d60c25972fcc9435e681669a5a&chksm=a6d9b1ca91ae38dcfbfc79fcf9f236c360c3285305a9f55daaa5489406a2eb33980d998cbc17&scene=21#wechat_redirect)  
5. 
[Go/Golang中的集合 – 使用映射和推荐的包](http://mp.weixin.qq.com/s?__biz=MjM5NzUwODgyNA==&mid=2247487439&idx=1&sn=0fa1eb1e5990df2c55dd6cfd2768c106&chksm=a6d9ac7891ae256e03cadb551ace818637e2b578aa69db9f0dedcfbf5e6327eb2346739ef619&scene=21#wechat_redirect)  
## 引用链接  
1. https://go101.org/article/memory-layout.html#size-and-padding  
2. https://go.dev/blog/swisstable  
3. https://en.wikipedia.org/wiki/Extendible_hashing  
4. https://en.wikipedia.org/wiki/Single_instruction,_multiple_data  
5. https://github.com/golang/go/issues/71255  
6. https://www.datadoghq.com/blog/go-memory-metrics/#heap-profiling  
7. https://tip.golang.org/doc/gc-guide#Memory_limit  
