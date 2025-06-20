#  你真的了解go语言中的切片吗？  
原创 小徐先生1212  小徐先生的编程世界   2023-06-03 16:12  
  
# 0 前言  
  
切片 slice 是 golang 中一个非常经典的数据结构，其定位可以类比于其他编程语言中的数组. 本文介绍的内容会分为 slice 的使用教程、问题讲解以及源码解析，走读的源码为 go v1.19.  
  
   
# 1 几个问题  
  
首先呢，我觉得使用 go 的朋友对于切片这个数据结构不会感到陌生，一些基本的概念和用法应该是可以做到了然于心的. 下面我先抛出一轮问题，大家可以思考并给出自己的答案，然后带着问题进入本文后半段的学习. 在第 2 章中，我们会进行原理补充，把问题涉及的拼图碎片一块块集齐；最后在第 3 章中，我们会正面给出第 1 章中所有问题的答案.  
  
下面，就正式开启灵魂拷问环节：  
## 1.1 问题1  
- • 初始化切片 s 长度和容量均为 10  
  
- • 在 s 的基础上追加 append 一个元素  
  
请问经过上述操作后，切片s 的内容、长度以及容量分别是什么？  
```
func Test_slice(t *testing.T){
    s := make([]int,10)  
    s = append(s,10)
    t.Logf("s: %v, len of s: %d, cap of s: %d",s,len(s),cap(s))
}
```  
  
   
## 1.2 问题2  
- • 初始化切片 s 长度为 0，容量为 10  
  
- • 在 s 的基础上追加 append 一个元素  
  
请问经过上述操作后，切片s 的内容、长度以及容量分别是什么？  
```
func Test_slice(t *testing.T){
    s := make([]int,0,10)  
    s = append(s,10)
    t.Logf("s: %v, len of s: %d, cap of s: %d",s,len(s),cap(s))
}
```  
  
   
## 1.3 问题3  
- • 初始化切片 s 长度为 10，容量为 11  
  
- • 在 s 的基础上追加 append 一个元素  
  
请问经过上述操作后，切片s 的内容、长度以及容量分别是什么？  
```
func Test_slice(t *testing.T){
    s := make([]int,10,11)  
    s = append(s,10)
    t.Logf("s: %v, len of s: %d, cap of s: %d",s,len(s),cap(s))
}
```  
  
   
## 1.4 问题4  
- • 初始化切片 s 长度为 10，容量为 12  
  
- • 截取切片 s index = 8 往后的内容赋给 s1  
  
求问 s1 的内容、长度以及容量分别是什么？  
```
func Test_slice(t *testing.T){
    s := make([]int,10,12)  
    s1 := s[8:]
    t.Logf("s1: %v, len of s1: %d, cap of s1: %d",s1,len(s1),cap(s1))
}
```  
  
   
## 1.5 问题5  
- • 初始化切片 s 长度为 10，容量为 12  
  
- • 截取切片 s index 为 [8,9) 范围内的元素赋给切片 s1  
  
求问 s1 的内容、长度以及容量分别是什么？  
```
func Test_slice(t *testing.T){
    s := make([]int,10,12)  
    s1 := s[8:9]
    t.Logf("s1: %v, len of s1: %d, cap of s1: %d",s1,len(s1),cap(s1))
}
```  
  
   
## 1.6 问题6  
- • 初始化切片 s 长度为 10，容量为 12  
  
- • 截取切片 s index = 8 往后的内容赋给 s1  
  
- • 修改 s1[0] 的值  
  
请问这个修改是否会影响到 s？ 此时，s 的内容是什么？  
```
func Test_slice(t *testing.T){
    s := make([]int,10,12)  
    s1 := s[8:]
    s1[0] = -1
    t.Logf("s: %v",s)
}
```  
  
   
## 1.7 问题7  
- • 初始化切片 s 长度为 10，容量为 12  
  
请问，访问 s[10] 是否会越界？  
```
func Test_slice(t *testing.T){
    s := make([]int,10,12)  
    v := s[10]
    // 求问，此时数组访问是否会越界
}
```  
  
   
## 1.8 问题8  
- • 初始化切片 s 长度为 10，容量为 12  
  
- • 截取 s 中 index = 8 后面的内容赋给 s1  
  
- • 在 s1 的基础上追加 []int{10,11,12} 3 个元素  
  
请问，经过上述操作时候，访问 s[10] 是否会越界？  
```
func Test_slice(t *testing.T){
    s := make([]int,10,12)  
    s1 := s[8:]
    s1 = append(s1,[]int{10,11,12}...)
    v := s[10]
    // ...
    // 求问，此时数组访问是否会越界
}
```  
  
   
## 1.9 问题9  
- • 初始化切片 s 长度为 10，容量为 12  
  
- • 截取切片 s index = 8 往后的内容赋给 s1  
  
- • 在方法 changeSlice 中，对 s1[0] 进行修改  
  
求问，经过上述操作之后，s 的内容是什么？  
```
func Test_slice(t *testing.T){
    s := make([]int,10,12)  
    s1 := s[8:]
    changeSlice(s1)
    t.Logf("s: %v",s)
}


func changeSlice(s1 []int){
  s1[0] = -1
}
```  
  
   
## 1.10 问题10  
- • 初始化切片 s 长度为 10，容量为 12  
  
- • 截取切片 s index = 8 往后的内容赋给 s1  
  
- • 在方法 changeSlice 中，对 s1 进行 apend 追加操作  
  
请问，经过上述操作后，s 以及 s1 的内容、长度和容量分别是什么？  
```
func Test_slice(t *testing.T){
    s := make([]int,10,12)  
    s1 := s[8:]
    changeSlice(s1)
    t.Logf("s: %v, len of s: %d, cap of s: %d",s, len(s), cap(s))
    t.Logf("s1: %v, len of s1: %d, cap of s1: %d",s1, len(s1), cap(s1))
}


func changeSlice(s1 []int){
  s1 = append(s1, 10)
}
```  
  
   
## 1.11 问题11  
- • 初始化切片 s，内容为 []int{0,1,2,3,4}  
  
- • 截取 s 中 index = 2 前面的内容（不含s[2]），并在此基础上追加 index = 3 后面的内容  
  
请问，经过上述操作后，s 的内容、长度和内容分别是什么？此时访问 s[4] 是否会越界？  
```
func Test_slice(t *testing.T){
    s := []int{0,1,2,3,4}
    s = append(s[:2],s[3:]...)
    t.Logf("s: %v, len: %d, cap: %d", s, len(s), cap(s))
    v := s[4] 
    // 是否会数组访问越界
}
```  
  
   
## 1.12 问题12  
- • 初始化切片 s 长度和容量均为 512  
  
- • 在 s 的基础上追加 append 一个元素  
  
请问经过上述操作后，切片s 的内容、长度以及容量分别是什么？  
```
func Test_slice(t *testing.T){
    s := make([]int,512)  
    s = append(s,1)
    t.Logf("len of s: %d, cap of s: %d",len(s),cap(s))
}
```  
  
   
  
   
# 2 使用及原理  
## 2.1 基本介绍  
  
go 语言中的切片对标于其他编程语言中通俗意义上的“数组”. 切片中的元素存放在一块内存地址连续的区域，使用索引可以快速检索到指定位置的元素；切片长度和容量是可变的，在使用过程中可以根据需要进行扩容.  
  
   
## 2.2 数据结构  
  
![](https://mmbiz.qpic.cn/sz_mmbiz_png/3ic3aBqT2ibZvgE26FViadhYD3bxFrzlX5LMpH8IpSx6xcY7YwyceXibrkEfuwk6OiaqY39xAR5ukacPetibsAhxibPRw/640?wx_fmt=png "")  
```
type slice struct {
    // 指向起点的地址
    array unsafe.Pointer
    // 切片长度
    len   int
    // 切片容量
    cap   int
}
```  
  
切片的类型定义如上，我们称之为 slice header，对应于每个 slice 实例，其中核心字段包括：  
- • array：指向了内存空间地址的起点. 由于 slice 数据存放在连续的内存空间中，后续可以根据索引 index，在起点的基础上快速进行地址偏移，从而定位到目标元素  
  
- • len：切片的长度，指的是逻辑意义上 slice 中实际存放了多少个元素  
  
- • cap：切片的容量，指的是物理意义上为 slice 分配了足够用于存放多少个元素的空间. 使用 slice 时，要求 cap 永远大于等于 len  
  
通过 slice 数据结构定义可以看到，每个 slice header 中存放的是内存空间的地址（array 字段），后续在传递切片的时候，相当于是对 slice header 进行了一次值拷贝，但内部存放的地址是相同的，因此对于 slice 本身属于引用传递操作  
  
此外，在这里我们聊到了切片的长度 len 和容量 cap 两个概念，这两个概念很重要，我们需要分清楚两者的区别，这一点会伴随我们研究切片的流程始终.  
  
   
## 2.3 初始化  
  
下面先来介绍下切片的初始化操作：  
- • 声明但不初始化  
  
下面给出的第一个例子，只是声明了 slice 的类型，但是并没有执行初始化操作，即 s 这个字面量此时是一个空指针 nil，并没有完成实际的内存分配操作.  
```
  var s []int 
```  
  
   
- • 基于 make 进行初始化  
  
make 初始化 slice 也分为两种方式, 第一种方式如下：  
```
  s := make([]int,8)
```  
  
此时会将切片的长度 len 和 容量 cap 同时设置为 8. 需要注意，切片的长度一旦被指定了，就代表对应位置已经被分配了元素，尽管设置的会是对应元素类型下的零值.  
  
   
  
第二种方式，是分别指定切片的长度 len 和容量 cap，代码如下：  
  
   
```
  s := make([]int,8,16)
```  
  
如上所示，代表已经在切片中设置了 8 个元素，会设置为对应类型的零值；cap = 16 代表为 slice 分配了用于存放 16 个元素的空间. 需要保证 cap >= len. 在 index 为 `[len, cap)` 的范围内，虽然内存空间已经分配了，但是逻辑意义上不存在元素，直接访问会 panic 报数组访问越界；但是访问 `[0,len)` 范围内的元素是能够正常访问到的，只不过会是对应元素类型下的零值.  
  
   
- • 初始化连带赋值  
  
初始化 slice 时还能一气呵成完成赋值操作. 如下所示：  
```
  s := []int{2,3,4}
```  
  
这样操作的话，会将 slice 长度 len 和容量 cap 均设置为 3，同时完成对这 3 个元素赋值.  
  
   
  
下面我们来一起过目一下切片初始化的源码，方法入口位于 golang 标准库文件 runtime/slice.go 文件的 makeslice 方法中：  
```
func makeslice(et *_type, len, cap int) unsafe.Pointer {
    // 根据 cap 结合每个元素的大小，计算出消耗的总容量
    mem, overflow := math.MulUintptr(et.size, uintptr(cap))
    if overflow || mem > maxAlloc || len < 0 || len > cap {
        // 倘若容量超限，len 取负值或者 len 超过 cap，直接 panic
        mem, overflow := math.MulUintptr(et.size, uintptr(len))
        if overflow || mem > maxAlloc || len < 0 {
            panicmakeslicelen()
        }
        panicmakeslicecap()
    }
    // 走 mallocgc 进行内存分配以及切片初始化
    return mallocgc(mem, et, true)
}
```  
  
上述方法核心步骤是  
- • 调用 math.MulUintptr 的方法，结合每个元素的大小以及切片的容量，计算出初始化切片所需要的内存空间大小  
  
- • 倘若内存空间超限，则直接抛出 panic  
  
- • 调用位于 runtime/malloc.go 文件中的 mallocgc 方法，为切片进行内存空间的分配  
  
（想了解关于更多关于内存分配的细节，可以阅读我之前发表的文章——Golang内存模型与分配机制）  
  
   
## 2.4 引用传递  
  
首先，我们捋清楚引用传递和值传递这两个概念的区别.  
  
![](https://mmbiz.qpic.cn/sz_mmbiz_png/3ic3aBqT2ibZvgE26FViadhYD3bxFrzlX5LXBrul6yuOnp3lGibibYNv70s7ibkf7xVrq1FkJOIUKKYkGXDeIUj6vC5A/640?wx_fmt=png "")  
  
引用传递，指的是，将实例的地址信息传递到方法中，这样在方法中会直接通过地址追溯到实例所在位置，因此执行的一些修改操作会直接影响到原实例.  
  
   
  
![](https://mmbiz.qpic.cn/sz_mmbiz_png/3ic3aBqT2ibZvgE26FViadhYD3bxFrzlX5LEEic6g4FKibrTDMgibJVvIoM3icicia43XxJPHBxNaG2xtazgk2nOnlu2V9Q/640?wx_fmt=png "")  
  
值传递，指的是对实例进行一轮拷贝，得到一个副本，然后将这个副本传递到方法中. 这样在方法内部发生的修改动作都作用于这个副本之上，而副本本身和实例是相互独立的，因此不会影响到原实例.  
  
   
  
今天我们聊到的 slice 属于引用传递的类型，下面给出一个使用示例：  
```
func Test_slice(t *testing.T){
  s := []int{2,3,4}
  // [2,3,4] -> [-1,3,4]
  changeSlice(s)
}


func changeSlice(s []int){
  s[0] = -1
}
```  
  
如代码所示，将主方法 Test_slice 中声明的切片 s 作为 changeSlice 方法的入参进行传递，同时在 changeSlice 方法中对 s 内的元素进行修改，这样是会直接影响到 Test_slice 中的切片 s 的.  
  
产生这个结果的原因就在于切片的传递是引用传递，而非值传递. 关于这一点，我们可以不用死记硬背，而是可以结合 2.2 小节中我们聊到的 slice header 数据结构，进行逻辑梳理：  
  
每个切片实例对应一个 slice header，其中存储了三个字段：  
- • 切片内存空间的起始地址 array；  
  
- • 切片长度 len；  
  
- • 以及切片容量 cap.  
  
综上，每次我们在方法间传递切片时，会对 slice header 实例本身进行一次值拷贝，然后将 slice header 的副本传递到局部方法中.  
  
然而，这个 slice header 副本中的 array 和原 slice 指向同一片内存空间，因此在局部方法中执行修改操作时，还会根据这个地址信息影响到原 slice 所属的内存空间，从而对内容发生影响.  
  
   
## 2.5 内容截取  
  
接下来我们聊聊 slice 的截取操作.  
  
我们可以修改 slice 下标的方式，进行 slice 内容的截取，形如 `s[a:b]` 的格式，其中 a b 代表切片的索引 index，左闭右开，比如 `s[a:b]` 对应的范围是 `[a,b)`，代表的是取切片 slice index = a ~ index = b-1 范围的内容.  
  
此外，这里我聊到的 a 和 b 是可以缺省的：  
- • 如果 a 缺省不填则默认取 0 ，则代表从切片起始位置开始截取. 比如 s[:b] 等价于 s[0:b]  
  
- • 如果 b 缺省不填，则默认取 len(s)，则代表末尾截取到切片长度 len 的终点，比如 s[a:] 等价于 s[a:len(s)]  
  
- • a 和 b 均缺省也是可以的，则代表截取整个切片长度的范围，比如 s[:] 等价于 s[0:len(s)]  
  
   
  
下面给出一个对 slice 执行截取操作的代码示例：  
```
func Test_slice(t *testing.T){
   s := []int{1,2,3,4,5}
   // s1: [2,3,4,5]
   s1 := s[1:]
   // s2: [1,2,3,4]
   s2 := s[:len(s)-1]
   // s3: [2,3,4] 
   s3 := s[1:len(s)-1]
   // ...
}
```  
  
   
  
在对切片 slice 执行截取操作时，本质上是一次引用传递操作，因为不论如何截取，底层复用的都是同一块内存空间中的数据，只不过，截取动作会创建出一个新的 slice header 实例.  
  
![](https://mmbiz.qpic.cn/sz_mmbiz_png/3ic3aBqT2ibZvgE26FViadhYD3bxFrzlX5LE3b7UgLlicutlIvVRutr41oKMfnc2ics8wweKgdTJJsbcIiaErN6NcbEA/640?wx_fmt=png "")  
```
  s := []int{2,3,4,5}
  s1 := s[1:]
  // ...
```  
  
以下面的代码为例，  
  
s1 = s[1:] 的操作，会创建出一个 s1 的 slice header，其中的字段 array 会在 s.array 的基础上向右偏移一个切片元素大小的数值；s1.len 和 s1.cap 也会以 s1 的起点为起点，以 s 原定的 len 和 cap 终点为终点，最终推算得出 s1.len = s.len - 1；s1.cap = s.cap - 1.  
  
   
## 2.6 元素追加  
  
下面介绍的是切片的追加操作. 通过 append 操作，可以在 slice 末尾，额外新增一个元素. 需要注意，这里的末尾指的是针对 slice 的长度 len 而言. 这个过程中倘若发现 slice 的剩余容量已经不足了，则会对 slice 进行扩容. 扩容有关的内容我们放到 2.7 小节再作展开.  
  
   
```
func Test_slice(t *testing.T){
    s := []int{2,3,4}  
    s = append(s,5)
    // s: [2,3,4,5]
}
```  
  
   
  
结合我个人的经验，一些 go 的初学者在对 slice 进行初始化以及赋值操作时，有可能会因为对 slice 中 len 和 cap 概念的混淆，最终出现错误的使用方式，形如下面这个代码示例：  
```
func Test_slice(t *testing.T){
    s := make([]int,5)
    for i := 0; i < 5; i++{
       s = append(s, i)
    }
    // 结果为：
    // s: [0,0,0,0,0,0,1,2,3,4]
}
```  
  
我们预期的操作时声明出一个长度为 5 的 slice，同时依次向其中填入 0,1,2,3,4 的五个元素，然而按照上述代码执行下来，得到的结果是事与愿违的，其原因在于  
- • 我们通过 make 操作，声明了一个长度和容量均为 5 的切片 s，此时前 5 个元素已经被填充为零值  
  
- • 接下来执行 append 操作时，只会在长度末尾进行追加. 最终会引发扩容，并最终得到结果为 [0,0,0,0,0,0,1,2,3,4,5]  
  
   
  
针对于我们意图，下面给出两个正确的使用示例：  
  
示例一：  
  
倘若大家希望使用 append 操作完成 slice 赋值，则应该在初始化 slice 时，给其设置不同的长度 len 和容量 cap 值，cap 和 len 之间的差值就是预留出来用于 append 操作的空间. 具体代码如下：  
```
func Test_slice(t *testing.T){
    s := make([]int,0,5)
    for i := 0; i < 5; i++{
       s = append(s, i)
    }
    // 结果为：
    // s: [0,1,2,3,4]
}
```  
  
   
  
示例二：  
  
我们将 slice 的长度和容量都设置为 5,然后通过遍历 slice 的方式进行执行位置元素的赋值（不使用 append 操作）：  
```
func Test_slice(t *testing.T){
    s := make([]int,5)
    for i := 0; i < 5; i++{
       s[i] = i
    }
    // 结果为：
    // s: [0,1,2,3,4]
}
```  
  
   
  
上面介绍的两种使用方式都是正确且规范的. 这里称之为规范的核心原因在于，我们在创建 slice 时，如果能够预估到其未来所需的容量空间，则应该提前分配好对应容量，避免在运行过程中频繁触发扩容操作，这样会对性能产生不利的影响.  
  
   
## 2.7 切片扩容  
  
下面我们捋一下切片扩容的流程. 当 slice 当前的长度 len 与容量 cap 相等时，下一次 append 操作就会引发一次切片扩容.  
```
    // len:4, cap: 4
    s := []int{2,3,4,5}
    // len:5, cap: 8    
    s = append(s,6)
```  
  
   
  
![](https://mmbiz.qpic.cn/sz_mmbiz_png/3ic3aBqT2ibZvgE26FViadhYD3bxFrzlX5LglIribUib8uTxAiahk2WFN6qjF9aF8u4PVVib2ShoRBZ5HWQ9Z1icTNaTgw/640?wx_fmt=png "")  
  
切片的扩容流程源码位于 runtime/slice.go 文件的 growslice 方法当中，其中核心步骤如下：  
- • 倘若扩容后预期的新容量小于原切片的容量，则 panic  
  
- • 倘若切片元素大小为 0（元素类型为 struct{}），则直接复用一个全局的 zerobase 实例，直接返回  
  
- • 倘若预期的新容量超过老容量的两倍，则直接采用预期的新容量  
  
- • 倘若老容量小于 256，则直接采用老容量的2倍作为新容量  
  
- • 倘若老容量已经大于等于 256，则在老容量的基础上扩容 1/4 的比例并且累加上 192 的数值，持续这样处理，直到得到的新容量已经大于等于预期的新容量为止  
  
- • 结合 mallocgc 流程中，对内存分配单元 mspan 的等级制度，推算得到实际需要申请的内存空间大小  
  
- • 调用 mallocgc，对新切片进行内存初始化  
  
- • 调用 memmove 方法，将老切片中的内容拷贝到新切片中  
  
- • 返回扩容后的新切片  
  
   
```go
func growslice(et *_type, old slice, cap int) slice {
    //... 
    if cap < old.cap {
        panic(errorString("growslice: cap out of range"))
    }


    if et.size == 0 {
        // 倘若元素大小为 0，则无需分配空间直接返回
        return slice{unsafe.Pointer(&zerobase), old.len, cap}
    }


    // 计算扩容后数组的容量
    newcap := old.cap
    // 取原容量两倍的容量数值
    doublecap := newcap + newcap
    // 倘若新的容量大于原容量的两倍，直接取新容量作为数组扩容后的容量
    if cap > doublecap {
        newcap = cap
    } else {
        const threshold = 256
        // 倘若原容量小于 256，则扩容后新容量为原容量的两倍
        if old.cap < threshold {
            newcap = doublecap
        } else {
            // 在原容量的基础上，对原容量 * 5/4 并且加上 192
            // 循环执行上述操作，直到扩容后的容量已经大于等于预期的新容量为止
            for 0 < newcap && newcap < cap {             
                newcap += (newcap + 3*threshold) / 4
            }
            // 倘若数值越界了，则取预期的新容量 cap 封顶
            if newcap <= 0 {
                newcap = cap
            }
        }
    }


    var overflow bool
    var lenmem, newlenmem, capmem uintptr
    // 基于容量，确定新数组容器所需要的内存空间大小 capmem
    switch {
    // 倘若数组元素的大小为 1，则新容量大小为 1 * newcap.
    // 同时会针对 span class 进行取整
    case et.size == 1:
        lenmem = uintptr(old.len)
        newlenmem = uintptr(cap)
        capmem = roundupsize(uintptr(newcap))
        overflow = uintptr(newcap) > maxAlloc
        newcap = int(capmem)
    // 倘若数组元素为指针类型，则根据指针占用空间结合元素个数计算空间大小
    // 并会针对 span class 进行取整
    case et.size == goarch.PtrSize:
        lenmem = uintptr(old.len) * goarch.PtrSize
        newlenmem = uintptr(cap) * goarch.PtrSize
        capmem = roundupsize(uintptr(newcap) * goarch.PtrSize)
        overflow = uintptr(newcap) > maxAlloc/goarch.PtrSize
        newcap = int(capmem / goarch.PtrSize)
    // 倘若元素大小为 2 的指数，则直接通过位运算进行空间大小的计算   
    case isPowerOfTwo(et.size):
        var shift uintptr
        if goarch.PtrSize == 8 {
            // Mask shift for better code generation.
            shift = uintptr(sys.Ctz64(uint64(et.size))) & 63
        } else {
            shift = uintptr(sys.Ctz32(uint32(et.size))) & 31
        }
        lenmem = uintptr(old.len) << shift
        newlenmem = uintptr(cap) << shift
        capmem = roundupsize(uintptr(newcap) << shift)
        overflow = uintptr(newcap) > (maxAlloc >> shift)
        newcap = int(capmem >> shift)
    // 兜底分支：根据元素大小乘以元素个数
    // 再针对 span class 进行取整     
    default:
        lenmem = uintptr(old.len) * et.size
        newlenmem = uintptr(cap) * et.size
        capmem, overflow = math.MulUintptr(et.size, uintptr(newcap))
        capmem = roundupsize(capmem)
        newcap = int(capmem / et.size)
    }




    // 进行实际的切片初始化操作
    var p unsafe.Pointer
    // 非指针类型
    if et.ptrdata == 0 {
        p = mallocgc(capmem, nil, false)
        // ...
    } else {
        // 指针类型
        p = mallocgc(capmem, et, true)
        // ...
    }
    // 将切片的内容拷贝到扩容后的位置 p 
    memmove(p, old.array, lenmem)
    return slice{p, old.len, newcap}
}
```  
  
   
## 2.8 元素删除  
  
从切片中删除元素的实现思路，本质上和切片内容截取的思路是一致的.  
  
比如，我们期望删除 slice 中的首个元素，在操作上等同于从切片 index = 1 开始向后进行内容截取：  
```
func Test_slice(t *testing.T){
    s := []int{0,1,2,3,4}
    // [1,2,3,4]
    s = s[1:]
}
```  
  
   
  
如果我们希望删除 slice 的尾部元素，则操作等价于截取切片内容，并将终点设置在 len(s) - 1 的位置：  
```
func Test_slice(t *testing.T){
    s := []int{0,1,2,3,4}
    // [0,1,2,3]
    s = s[0:len(s)-1]
}
```  
  
   
  
如果需要删除 slice 中间的某个元素，操作思路则是采用内容截取加上元素追加的复合操作，可以先截取待删除元素的左侧部分内容，然后在此基础上追加上待删除元素后侧部分的内容：  
```
func Test_slice(t *testing.T){
    s := []int{0,1,2,3,4}
    // 删除 index = 2 的元素
    s = append(s[:2],s[3:]...)
    // s: [0,1,3,4], len: 4, cap: 5
    t.Logf("s: %v, len: %d, cap: %d", s, len(s), cap(s))
}
```  
  
   
  
最后，当我们需要删除 slice 中的所有元素时，也可以采用切片内容截取的操作方式：s[:0]. 这样操作后，slice header 中的指针 array 仍指向远处，但是逻辑意义上其长度 len 已经等于 0，而容量 cap 则仍保留为原值.  
```
func Test_slice(t *testing.T){
    s := []int{0,1,2,3,4}
    s = s[:0]
    // s: [], len: 0, cap: 5
    t.Logf("s: %v, len: %d, cap: %d", s, len(s), cap(s))
}
```  
  
   
## 2.9 切片拷贝  
  
slice 的拷贝可以分为简单拷贝和完整拷贝两种类型.  
  
要实现简单拷贝，我们只需要对切片的字面量进行赋值传递即可，这样相当于创建出了一个新的 slice header 实例，但是其中的指针 array、容量 cap 和长度 len 仍和老的 slice header 实例相同.  
  
操作实例如下，最终输出的结果中，s 和 s1 的地址是一致的.  
```
func Test_slice(t *testing.T) {
    s := []int{0, 1, 2, 3, 4}
    s1 := s
    t.Logf("address of s: %p, address of s1: %p", s, s1)
}
```  
  
   
  
这里再声明一下，切片的截取操作也属于是简单拷贝，以下面操作代码为例，s 和 s1 会使用同一片内存空间，只不过地址起点位置偏移了一个元素的长度. s1 和 s 的地址，刚好相差 8 个 byte.  
```
func Test_slice(t *testing.T) {
    s := []int{0, 1, 2, 3, 4}
    s1 := s[1:]
    t.Logf("address of s: %p, address of s1: %p", s, s1)
}
```  
  
   
  
slice 的完整复制，指的是会创建出一个和 slice 容量大小相等的独立的内存区域，并将原 slice 中的元素一一拷贝到新空间中.  
  
在实现上，slice 的完整复制可以调用系统方法 copy，代码示例如下，通过日志打印的方式可以看到，s 和 s1 的地址是相互独立的：  
```
func Test_slice(t *testing.T) {
    s := []int{0, 1, 2, 3, 4}
    s1 := make([]int, len(s))
    copy(s1, s)
    t.Logf("s: %v, s1: %v", s, s1)
    t.Logf("address of s: %p, address of s1: %p", s, s1)
}
```  
  
   
# 3 问题解答  
## 3.1 问题1  
```
func Test_slice(t *testing.T){
    s := make([]int,10)  
    s = append(s,10)
    t.Logf("s: %v, len of s: %d, cap of s: %d",s,len(s),cap(s))
}
```  
  
答案为：  
```
s: [0 0 0 0 0 0 0 0 0 0 10], len of s: 11, cap of s: 20
```  
  
原因在于：  
  
学完 2.3 小节的内容，我们了解到，基于 make([]int, 10) 的方式初始化切片的话其长度 len 和容量 cap 均为 10，且前10个元素是已经切实被分配过的（虽然会被填充为零值）. 此时进行 append 操作，会在末尾进行元素追加，由于切片的长度和容量是相等的，因此已经没有剩余可用的空间了，于是会进一步引发切片的扩容操作.  
  
基于 2.7 小节，我们了解到在切片原容量小于 256 的情况下，扩容时会采用原容量的2倍作为新的容量，于是在新切片中，长度增加为 11，而容量则翻倍变成 20.  
  
   
## 3.2 问题2  
```
func Test_slice(t *testing.T){
    s := make([]int,0,10)  
    s = append(s,10)
    t.Logf("s: %v, len of s: %d, cap of s: %d",s,len(s),cap(s))
}
```  
  
答案为：  
```
s: [10], len of s: 1, cap of s: 10
```  
  
原因在于：  
  
make([]int, 0, 10) 的方式使得切片长度为 0，容量为 10，实际上还有长度为 10 的缓存空间. 于是这一次 append 操作，会直接使用已有的空间，不会引发扩容. 结果中，切片长度从 0 增加为 1，容量则维持为 10 不变.  
  
   
## 3.3 问题3  
```
func Test_slice(t *testing.T){
    s := make([]int,10,11)  
    s = append(s,10)
    t.Logf("s: %v, len of s: %d, cap of s: %d",s,len(s),cap(s))
}
```  
  
答案为：  
```
s: [0 0 0 0 0 0 0 0 0 0 10], len of s: 11, cap of s: 11
```  
  
问题3和问题2类似，由于容量大于长度，因此仍有足够的空间，这次 append 操作不会引发扩容.  
  
   
## 3.4 问题4  
```
func Test_slice(t *testing.T){
    s := make([]int,10,12)  
    s1 := s[8:]
    t.Logf("s1: %v, len of s1: %d, cap of s1: %d",s1,len(s1),cap(s1))
}
```  
  
   
  
答案为：  
```
s1: [0 0], len of s1: 2, cap of s1: 4
```  
  
截取操作会以 s[8] 作为内存空间的起点，截取所得新切片 s1 的长度和容量强依赖于原切片 s 的长度和容量，并在此基础上减去头部 8 个未使用到的单位.  
  
   
## 3.5 问题5  
```
func Test_slice(t *testing.T){
    s := make([]int,10,12)  
    s1 := s[8:9]
    t.Logf("s1: %v, len of s1: %d, cap of s1: %d",s1,len(s1),cap(s1))
}
```  
  
答案为：  
```
s1: [0], len of s1: 1, cap of s1: 4
```  
  
问题5和问题4类似，我们需要注意虽然 s[8:9] 的截取操作限定了 s1 的右边界，但这只是长度意义上的，对于容量，s1 仍然和 s 保持强关联性.  
  
   
## 3.6 问题6  
```
func Test_slice(t *testing.T){
    s := make([]int,10,12)  
    s1 := s[8:]
    s1[0] = -1
    t.Logf("s: %v",s)
}
```  
  
答案为：  
```
s: [0 0 0 0 0 0 0 0 -1 0]
```  
  
s1 是在 s 基础上截取得到的，属于一次引用传递，底层共用同一片内存空间，其中 s[x] 等价于 s1[x+8]. 因此修改了 s1[0] 会直接影响到 s[8] .  
  
   
## 3.7 问题7  
```
func Test_slice(t *testing.T){
    s := make([]int,10,12)  
    v := s[10]
    // 求问，此时数组访问是否会越界
}
```  
  
答案：会发生 panic.  
  
初始化时设定了切片长度为10，容量为 12. 容量是物理意义上的，但长度是逻辑意义上的，判断**是否越界以逻辑意义为准**，因此 index = 10 已经越界.  
  
   
## 3.8 问题8  
```
func Test_slice(t *testing.T){
    s := make([]int,10,12)  
    s1 := s[8:]
    s1 = append(s1,[]int{10,11,12}...)
    v := s[10]
    // ...
    // 求问，此时数组访问是否会越界
}
```  
  
答案：会发生 panic.  
- • 在 s 的基础上截取产生了 s1，此时 s1 和 s 会拥有两个独立的 slice header.  
  
- • 接下来执行 append 操作时，由于 s 预留的空间不足，s1 会发生扩容  
  
- • s1 扩容后，会被迁移到新的空间地址，此时 s1 已经和 s 做到真正意义上的完全独立，意味着修改 s1 不再会影响到 s  
  
- • s 继续维持原本的长度值 10 和容量值 12，因此访问 s[10] 会panic  
  
   
## 3.9 问题9  
```
func Test_slice(t *testing.T){
    s := make([]int,10,12)  
    s1 := s[8:]
    changeSlice(s1)
    t.Logf("s: %v",s)
}


func changeSlice(s1 []int){
  s1[0] = -1
}
```  
  
答案：  
```
s: [0 0 0 0 0 0 0 0 -1 0]
```  
  
切片在传递时属于引用传递，且 s1[0] 和 s[8] 指向同一个元素. 因此在局部方法中，修改了 s1[0] 会直接影响到 s[8] 的内容.  
  
   
## 3.10 问题10  
```
func Test_slice(t *testing.T){
    s := make([]int,10,12)  
    s1 := s[8:]
    changeSlice(s1)
    t.Logf("s: %v, len of s: %d, cap of s: %d",s, len(s), cap(s))
    t.Logf("s1: %v, len of s1: %d, cap of s1: %d",s1, len(s1), cap(s1))
}


func changeSlice(s1 []int){
  s1 = append(s1, 10)
}
```  
  
答案：  
```
s: [0 0 0 0 0 0 0 0 0 0], len of s: 10, cap of s: 12
s1: [0 0], len of s1: 2, cap of s1: 4
```  
  
虽然切片是引用传递，但是在方法调用时，传递的会是一个新的 slice header.  
  
因此在局部方法 changeSlice 中，虽然对 s1 进行了 append 操作，但这会在局部方法中这个独立的 slice header 中生效，不会影响到原方法 Test_slice 当中的 s 和 s1 的长度和容量.  
  
   
## 3.11 问题11  
```
func Test_slice(t *testing.T){
    s := []int{0,1,2,3,4}
    s = append(s[:2],s[3:]...)
    t.Logf("s: %v, len: %d, cap: %d", s, len(s), cap(s))
    v := s[4] 
    // 是否会数组访问越界
}
```  
  
答案：  
  
输出内容为：  
```
s: [0 1 3 4], len: 4, cap: 5
```  
  
会发生 panic  
  
执行完上述 append 操作之后，s 的实际长度为 4，容量维持不变为 5. 此时访问 s[4]会发生数组越界的错误.  
  
   
## 3.12 问题12  
```
func Test_slice(t *testing.T){
    s := make([]int,512)  
    s = append(s,1)
    t.Logf("len of s: %d, cap of s: %d",len(s),cap(s))
}
```  
  
答案：  
```
len: 513, cap: 848
```  
  
问题11的内容看起来平平无奇，为什么我会选择将其作为压轴呢？原因在于其中暗藏了两个细节，使得这个问题远没有其表面上看上去的那么简单.  
  
首先，如 2.7 小节中谈到的，由于切片 s 原有容量为 512，已经超过了阈值 256，因此对其进行扩容操作会采用的计算共识为 512 * (512 + 3\*256)/4 = 832  
  
其次，在真正申请内存空间时，我们会根据切片元素大小乘以容量计算出所需的总空间大小，得出所需的空间为 8byte * 832 = 6656 byte  
  
再进一步，结合分配内存的 mallocgc 流程，为了更好地进行内存空间对其，golang 允许产生一些有限的内部碎片，对拟申请空间的 object 进行大小补齐，最终 6656 byte 会被补齐到 6784 byte 的这一档次. （内存分配时，对象分档以及与 mspan 映射细节可以参考 golang 标准库 runtime/sizeclasses.go 文件，也可以阅读我的文章了解更多细节——golang 内存模型与分配机制）  
```
// class  bytes/obj  bytes/span  objects  tail waste  max waste  min align
//     1          8        8192     1024           0     87.50%          8
//     2         16        8192      512           0     43.75%         16
//     3         24        8192      341           8     29.24%          
// ...
//    48       6528       32768        5         128      6.23%        128
//    49       6784       40960        6         256      4.36%        128 
```  
  
再终，在 mallocgc 流程中，我们为扩容后的新切片分配到了 6784 byte 的空间，于是扩容后实际的新容量为 cap = 6784/8 = 848.  
  
   
# 4 总结  
  
本文和大家介绍了 golang 中经典的数据结构——切片 slice：  
- • slice 是一个长度可变的连续数据序列，在实现上基于一个 slice header 组成，其中包含的字段包括：指向内存空间地址起点的指针 array、一个表示了存储数据长度的 len 和分配空间长度的 cap  
  
- • 由于 slice 在传递过程中，本质上传递的是 slice header 实例中的内存地址 array，因此属于引用传递  
  
- • slice 在扩容时，遵循如下机制:  
  
- • 如果扩容时预期的新容量超过原容量的两倍，直接取预期的新容量  
  
- • 如果原容量小于 256，直接取原容量的两倍作为新容量  
  
- • 如果原容量大于等于 256，在原容量 n 的基础上循环执行 n += (n+3\*256)/4 的操作，直到 n 大于等于预期新容量，并取 n 作为新容量  
  
- • 最后还需要友情提示一下，slice 不是并发安全的数据结构，大家在使用时请务必注意并发安全问题.  
