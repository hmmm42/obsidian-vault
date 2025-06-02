#  Golang 垃圾回收原理分析   
原创 小徐先生1212  小徐先生的编程世界   2023-02-10 23:41  
  
# 0 前言  
  
近期在和大家一起探讨 Golang 内存管理机制.  
  
本系列内容分为两部分，第一部分谈及 Golang 内存模型以及内存分配机制，第二部分和大家讨论 Golang 的垃圾回收机制.  
  
本文是其中第二部分. 由于GC模块内容篇幅不小，且笔者近期工作繁忙，因此这部分不得不拆为上下两篇.  
  
本文是上篇，在理论层面对Golang GC展开介绍，下篇将于下周发出，届时会基于源码走读的方式对理论进行补充论证.  
  
   
# 1 垃圾回收算法  
## 1.1 背景介绍  
  
垃圾回收（Garbage Collection，简称 GC）是一种内存管理策略，由垃圾收集器以类似守护协程的方式在后台运作，按照既定的策略为用户回收那些不再被使用的对象，释放对应的内存空间.  
  
（1）GC 带来的优势包括：  
- • 屏蔽内存回收的细节  
  
拥有 GC 能力的语言能够为用户屏蔽复杂的内存管理工作，使用户更好地聚焦于核心的业务逻辑.  
- • 以全局视野执行任务  
  
现代软件工程项目体量与日剧增，一个项目通常由团体协作完成，研发人员负责各自模块的同时，不可避免会涉及到临界资源的使用. 此时由于缺乏全局的视野，手动对内存进行管理无疑会增加开发者的心智负担. 因此，将这部分工作委托给拥有全局视野的垃圾回收模块来完成，方为上上之策.  
  
（2）GC 带来的劣势：  
- • 提高了下限但降低了上限  
  
将释放内存的工作委托给垃圾回收模块，研发人员得到了减负，但同时也失去了控制主权. 除了运用有限的GC调优参数外，更多的自由度都被阉割，需要向系统看齐，服从设定.  
- • 增加了额外的成本  
  
全局的垃圾回收模块化零为整，会需要额外的状态信息用以存储全局的内存使用情况. 且部分时间需要中断整个程序用以支持垃圾回收工作的执行，这些都是GC额外产生的成本.  
  
（3）GC 的总体评价  
  
除开少量追求极致速度的特殊小规模项目之外，在绝大多数高并发项目中，GC模块都为我们带来了极大的裨益，已经成为一项不可或缺的能力.  
  
下面几类经典的垃圾回收算法进行介绍，算是一些比较老生常谈的内容.  
  
   
## 1.2 标记清扫  
  
![](https://mmbiz.qpic.cn/mmbiz_png/3ic3aBqT2ibZsX03L7kZaOrjpArjV5Tfmibiasge6gHfxHDZaVTK28XboJicMVN5vTeVmexSZiahPHgoEGR6rTt8yNHA/640?wx_fmt=png "")  
  
标记清扫（Mark-Sweep）算法，分为两步走：  
- • 标记：标记出当前还存活的对象  
  
- • 清扫：清扫掉未被标记到的垃圾对象  
  
这是一种类似于排除法的间接处理思路，不直接查找垃圾对象，而是标记存活对象，从而取补集推断出垃圾对象.  
  
至于标记清扫算法的不足之处，通过上图也得以窥见一二，那就是会产生内存碎片. 经过几轮标记清扫之后，空闲的内存块可能零星碎片化分布，此时倘若有大对象需要分配内存，可能会因为内存空间无法化零为整从而导致分配失败.  
  
   
## 1.3 标记压缩  
  
![](https://mmbiz.qpic.cn/mmbiz_png/3ic3aBqT2ibZsX03L7kZaOrjpArjV5TfmibnibespicI0XqXuj5tttlZ8Aer9sTN4LmXIfzcLTyXxqb5xKIb2kVuoibA/640?wx_fmt=png "")  
  
标记压缩（Mark-Compact）算法，是在标记清扫算法的基础上做了升级，在第二步”清扫“的同时还会对存活对象进行压缩整合，使得整体空间更为紧凑，从而解决内存碎片问题.  
  
标记压缩算法在功能性上呈现得很出色，而其存在的缺陷也很简单，就是实现时会有很高的复杂度.  
  
   
## 1.4 半空间复制  
  
![](https://mmbiz.qpic.cn/mmbiz_png/3ic3aBqT2ibZsX03L7kZaOrjpArjV5TfmibwOty0ClMclyHawH5hG6galeRYOYgGkvFdlHicx5yVI8PbJS5rWTia1UA/640?wx_fmt=png "")  
  
相信用过 Java 的同学对半空间复制（Semispace Copy）算法并不会感到陌生，它的核心点如下：  
- • 分配两片相等大小的空间，称为 fromspace 和 tospace  
  
- • 每轮只使用 fromspace 空间，以GC作为分水岭划分轮次  
  
- • GC时，将fromspace存活对象转移到tospace中，并以此为契机对空间进行压缩整合  
  
- • GC后，交换fromspace和tospace，开启新的轮次  
  
显然，半空间复制算法应用了以空间换取时间的优化策略，解决了内存碎片的问题，也在一定程度上降低了压缩空间的复杂度. 但其缺点也同样很明显——比较浪费空间.  
  
   
## 1.5 引用计数  
  
![](https://mmbiz.qpic.cn/mmbiz_png/3ic3aBqT2ibZsX03L7kZaOrjpArjV5Tfmibz6EWQR8Oq0RJlm08j1IRrPNta9atBVticicjG3rlg02xyWk5GCHXd3bg/640?wx_fmt=png "")  
  
引用计数（Reference Counting）算法是很简单高效的：  
- • 对象每被引用一次，计数器加1  
  
- • 对象每被删除引用一次，计数器减1  
  
- • GC时，把计数器等于 0 的对象删除  
  
然而，这个朴素的算法存在一个致命的缺陷：无法解决循环引用或者自引用问题.  
  
   
  
本章对垃圾回收算法的背景知识做了补充介绍，下一章我们来看看，在此基础上，Golang的GC模块做了怎样的设计与取舍.  
# 2 Golang 中的垃圾回收  
  
抛开漫长的进化史不谈，Golang 在 1.8版本之后，GC策略框架已经奠定，就是并发三色标记法+混合写屏障机制，下面我们逐一展开介绍.  
## 2.1 三色标记法  
==本质上就是 BFS==
  
![](https://mmbiz.qpic.cn/mmbiz_png/3ic3aBqT2ibZsX03L7kZaOrjpArjV5TfmibVhKyibUKRMIL8PHkLoicboTAicWC89UwtaHRcQ9Vx3TfddtXX3ibS4255w/640?wx_fmt=png "")  
  
Golang GC 中用到的三色标记法属于标记清扫-算法下的一种实现，由荷兰的计算机科学家 Dijkstra 提出，下面阐述要点：  
- • 对象分为三种颜色标记：黑、灰、白  
  
- • 黑对象代表，对象自身存活，且其指向对象都已标记完成  
  
- • 灰对象代表，对象自身存活，但其指向对象还未标记完成  
  
- • 白对象代表，对象尙未被标记到，可能是垃圾对象  
  
- • 标记开始前，将根对象（全局对象、栈上局部变量等）置黑，将其所指向的对象置灰  
  
- • 标记规则是，从灰对象出发，将其所指向的对象都置灰. 所有指向对象都置灰后，当前灰对象置黑  
  
- • 标记结束后，白色对象就是不可达的垃圾对象，需要进行清扫.  
  
   
## 2.2 并发垃圾回收  
  
![](https://mmbiz.qpic.cn/mmbiz_png/3ic3aBqT2ibZsX03L7kZaOrjpArjV5TfmibPpc2h4YV5wn4ABAWk7LhFt26Bqhgw5Oc2o8RsfJDzKibTT44LakOkZw/640?wx_fmt=png "")  
  
Golang 1.5 版本是个分水岭，在此之前，GC时需要停止全局的用户协程，专注完成GC工作后，再恢复用户协程，这样做在实现上简单直观，但是会对用户造成不好的体验.  
  
   
  
![](https://mmbiz.qpic.cn/mmbiz_png/3ic3aBqT2ibZsX03L7kZaOrjpArjV5Tfmib33NoKatxd9zHvIICmVIrZSsgqiaG52I5RGtyBvLhm6ibibnAjibYoicnItQ/640?wx_fmt=png "")  
  
自1.5版本以来，Golang引入了并发垃圾回收机制，允许用户协程和后台的GC协程并发运行，大大地提高了用户体验. 但“并发”是一个值得大家警惕的字眼. 用户协程运行时可能对对象间的引用关系进行调整，这会严重打乱GC三色标记时的标记秩序. 这些问题，我们将在2.3小节展开介绍.  
  
   
## 2.3 几个问题  
  
首先在（1）（2）两个问题中，讨论一下并发垃圾回收机制下，可能产生的问题.  
  
   
  
（1）Golang 并发垃圾回收可能存在漏标问题  
  
![](https://mmbiz.qpic.cn/mmbiz_png/3ic3aBqT2ibZsX03L7kZaOrjpArjV5TfmibsxNIGyOJkIU4gfDmUmNrMhPHFAicugGQnnrVJX16lIBKPSicbLAXhDdA/640?wx_fmt=png "")  
  
漏标问题指的是在用户协程与GC协程并发执行的场景下，部分存活对象未被标记从而被误删的情况. 这一问题产生的过程如下：  
- • 条件：初始时刻，对象B持有对象C的引用  
  
- • moment1：GC协程下，对象A被扫描完成，置黑；此时对象B是灰色，还未完成扫描  
  
- • momen2：用户协程下，对象A建立指向对象C的引用  
  
- • moment3：用户协程下，对象B删除指向对象C的引用  
  
- • moment4：GC协程下，开始执行对对象B的扫描  
  
在上述场景中，由于GC协程在B删除C的引用后才开始扫描B，因此无法到达C. 又因为A已经被置黑，不会再重复扫描，因此从扫描结果上看，C是不可达的.  
  
然而事实上，C应该是存活的（被A引用），而GC结束后会因为C仍为白色，因此被GC误删.  
  
漏标问题是无法接受，其引起的误删现象可能会导致程序出现致命的错误. 针对漏标问题，Golang 给出的解决方案是屏障机制的使用，这部分内容将在本文第3章进一步展开.  
  
   
  
（2）Golang 并发垃圾回收可能存在多标问题  
  
![](https://mmbiz.qpic.cn/mmbiz_png/3ic3aBqT2ibZsX03L7kZaOrjpArjV5Tfmibnib47D75UtmEnVVue9Xs3iaRGADUnEmvxQQpmhM3l7gT2AgyP7kwic31A/640?wx_fmt=png "")  
  
多标问题指的是在用户协程与GC协程并发执行的场景下，部分垃圾对象被误标记从而导致GC未按时将其回收的问题. 这一问题产生的过程如下：  
- • 条件：初始时刻，对象A持有对象B的引用  
  
- • moment1：GC协程下，对象A被扫描完成，置黑；对象B被对象A引用，因此被置灰  
  
- • momen2：用户协程下，对象A删除指向对象B的引用  
  
上述场景引发的问题是，在事实上，B在被A删除引用后，已成为垃圾对象，但由于其事先已被置灰，因此最终会更新为黑色，不会被GC删除.  
  
错标问题对比于漏标问题而言，是相对可以接受的. 其导致本该被删但仍侥幸存活的对象被称为“浮动垃圾”，至多到下一轮GC，这部分对象就会被GC回收，因此错误可以得到弥补.  
  
   
  
（3）Golang 垃圾回收如何解决内存碎片问题？  
  
![](https://mmbiz.qpic.cn/mmbiz_png/3ic3aBqT2ibZsX03L7kZaOrjpArjV5Tfmib9FWvgEH9f1p226icgE7owVcAMLe0E0YfA1sWLseRV6bh0FSCVOFZUoQ/640?wx_fmt=png "")  
  
1.2 小节中有提及，标记清扫算法会存在产生“内存碎片”的缺陷. 那么采用标记清扫算法的Golang GC模块要如何化解这一问题呢？  
  
在笔者一周前发布的文章—— “Golang 内存模型与分配机制”的介绍中已经能够给出这一问题的答复. Golang采用 TCMalloc 机制，依据对象的大小将其归属为到事先划分好的spanClass当中，这样能够消解外部碎片的问题，将问题限制在相对可控的内部碎片当中.  
  
基于此，Golang选择采用实现上更为简单的标记清扫算法，避免使用复杂度更高的标记压缩算法，因为在 TCMalloc 框架下，后者带来的优势已经不再明显.  
  
   
  
（4）Golang为什么不选择分代垃圾回收机制？  
  
![](https://mmbiz.qpic.cn/mmbiz_png/3ic3aBqT2ibZsX03L7kZaOrjpArjV5Tfmibb5pjZjK4IGqIH6aiaQNTkUMBPflJ9r6lKICDfURDyeEvLozEk8KyeNQ/640?wx_fmt=png "")  
  
分代算法指的是，将对象分为年轻代和老年代两部分（或者更多），采用不同的GC策略进行分类管理. 分代GC算法有效的前提是，绝大多数年轻代对象都是朝生夕死，拥有更高的GC回收率，因此适合采用特别的策略进行处理.  
  
然而Golang中存在**内存逃逸**机制，会在编译过程中将生命周期更长的对象转移到堆中，将生命周期短的对象分配在栈上，并以栈为单位对这部分对象进行回收.  
  
综上，内存逃逸机制减弱了分代算法对Golang GC所带来的优势，考虑分代算法需要产生额外的成本（如不同年代的规则映射、状态管理以及额外的写屏障），Golang 选择不采用分代GC算法.  
  
   
# 3 屏障机制  
  
本章介绍屏障有关的内容，主要是为了解决2.3小节中提及的并发GC下的漏标问题.  
## 3.1 强弱三色不变式  
  
漏标问题的本质就是，一个已经扫描完成的黑对象指向了一个被灰\白对象删除引用的白色对象. 构成这一场景的要素拆分如下：  
  
（1）黑色对象指向了白色对象  
  
（2）灰、白对象删除了白色对象  
  
（3）（1）、（2）步中谈及的白色对象是同一个对象  
  
（4）（1）发生在（2）之前  
  
   
  
一套用于解决漏标问题的方法论称之为强弱三色不变式：  
- • 强三色不变式：白色对象不能被黑色对象直接引用（直接破坏（1））  
  
- • 弱三色不变式：白色对象可以被黑色对象引用，但要从某个灰对象出发仍然可达该白对象（间接破坏了（1）、（2）的联动）  
  
   
## 3.2 插入写屏障  
  
![](https://mmbiz.qpic.cn/mmbiz_png/3ic3aBqT2ibZsX03L7kZaOrjpArjV5TfmibaVibfkBYl8ILibtxQv8WsLCiaZMwzQSpNtce15zcs2e2JJicYcibvPmXaJg/640?wx_fmt=png "")  
  
屏障机制类似于一个回调保护机制，指的是在完成某个特定动作前，会先完成屏障成设置的内容.  
  
插入写屏障（Dijkstra）的目标是实现强三色不变式，保证当一个黑色对象指向一个白色对象前，会先触发屏障将白色对象置为灰色，再建立引用.  
  
如果所有流程都能保证做到这一点，那么 3.1 小节中的（1）就会被破坏，漏标问题得以解决.  
  
   
## 3.3 删除写屏障  
  
![](https://mmbiz.qpic.cn/mmbiz_png/3ic3aBqT2ibZsX03L7kZaOrjpArjV5TfmibHQQ43dnDQfcNudRILbIA6xsGaFwNtfqFEQDHsCNp3kbLldmuLTYBHA/640?wx_fmt=png "")  
  
删除写屏障（Yuasa barrier）的目标是实现弱三色不变式，保证当一个白色对象即将被上游删除引用前，会触发屏障将其置灰，之后再删除上游指向其的引用.  
  
这一流程中，3.1小节的步骤（2）会被破坏，漏标问题得以解决.  
  
   
## 3.4 混合写屏障  
  
结合3.2 3.3小节来看，插入写屏障、删除写屏障二者择其一，即可解决并发GC的漏标问题，至于错标问题，则采用容忍态度，放到下一轮GC中进行延后处理即可.  
  
然而真实场景中，需要补充一个新的设定——**屏障机制无法作用于栈对象**.  
  
这是因为栈对象可能涉及频繁的轻量操作，倘若这些高频度操作都需要一一触发屏障机制，那么所带来的成本将是无法接受的.  
  
在这一背景下，单独看插入写屏障或删除写屏障，都无法真正解决漏标问题，除非我们引入额外的Stop the world（STW）阶段，对栈对象的处理进行兜底。  
  
为了消除这个额外的 STW 成本，Golang 1.8 引入了混合写屏障机制，可以视为糅合了插入写屏障+删除写屏障的加强版本，要点如下：  
- • GC 开始前，以栈为单位分批扫描，将栈中所有对象置黑  
  
- • GC 期间，栈上新创建对象直接置黑  
  
- • 堆对象正常启用插入写屏障  
  
- • 堆对象正常启用删除写屏障  
  
下面我们通过 3.5 小节的几个 show case，来论证混合写屏障机制是否真的能解决并发GC下的各种极端场景问题.  
## 3.5 show case  
  
（1）case 1：堆对象删除引用，栈对象建立引用  
  
   
  
![](https://mmbiz.qpic.cn/mmbiz_png/3ic3aBqT2ibZsX03L7kZaOrjpArjV5Tfmib0PFRxUrFryicq6TW7qN5aQibT6aD9aE3Eo0oPibbmKnthQZX21pshcic6Q/640?wx_fmt=png "")  
- • 背景：存在栈上对象A，黑色（扫描完）；  
  
存在堆上对象B，白色（未被扫描）；  
  
存在堆上对象C，被堆上对象B引用，白色（未被扫描）  
- • moment1：A建立对C的引用，由于栈无屏障机制，因此正常建立引用，无额外操作  
  
- • moment2：B尝试删除对C的引用，删除写屏障被触发，C被置灰，因此不会漏标  
  
   
  
（2）case 2：一个堆对象删除引用，成为另一个堆对象下游  
  
![](https://mmbiz.qpic.cn/mmbiz_png/3ic3aBqT2ibZsX03L7kZaOrjpArjV5TfmibxaRBiaBV6h44eqG5fA92WuDGbtXE5XIibyI7QLbmgMLwxkAndaqDWUSw/640?wx_fmt=png "")  
- • 背景：存在堆上对象A，白色（未被扫描）；  
  
存在堆上对象B，黑色（已完成扫描）；  
  
存在堆上对象C，被堆上对象B引用，白色（未被扫描）  
- • moment1：B尝试建立对C的引用，插入写屏障被触发，C被置灰  
  
- • moment2：A删除对C的引用，此时C已置灰，因此不会漏标  
  
   
  
（3）case 3：栈对象删除引用，成为堆对象下游  
  
![](https://mmbiz.qpic.cn/mmbiz_png/3ic3aBqT2ibZsX03L7kZaOrjpArjV5TfmibxHWaKDFs60CDNWs6NvCFaBibqe0PCFoMibUe7Ptc1xAicu5aFwpEP2LYg/640?wx_fmt=png "")  
- • 背景：存在栈上对象A，白色（未完成扫描，说明对应的栈未扫描）；  
  
存在堆上对象B，黑色（已完成扫描）；  
  
存在堆上对象C，被栈上对象A引用，白色（未被扫描）  
- • moment1：B尝试建立对C的引用，插入写屏障被触发，C被置灰  
  
- • moment2：A删除对C的引用，此时C已置灰，因此不会漏标  
  
   
  
（4）case 4：一个栈中对象删除引用，**另一个栈**中对象建立引用  
  
![](https://mmbiz.qpic.cn/mmbiz_png/3ic3aBqT2ibZsX03L7kZaOrjpArjV5TfmibyjmjfS5mTiaH4EKOuKpDdWToJWfy9iaBvLg9AcicHu8bRqanQk7jCZZ1w/640?wx_fmt=png "")  
- • 背景：存在栈上对象A，白色（未扫描，这是因为对应的栈还未开始扫描）；  
  
存在栈上对象B，黑色（已完成扫描，说明对应的栈均已完成扫描）；  
  
存在堆上对象C，被栈上对象A引用，白色（未被扫描）  
- • moment1：B建立对C的引用；  
  
- • moment2：A删除对C的引用.  
  
- • 结论：这种场景下，C要么已然被置灰，要么从某个灰对象触发仍然可达C.  
  
- • 原因在于，对象的引用不是从天而降，一定要有个来处. 当前 case 中，对象B能建立指向C的引用，至少需要满足如下三个条件之一：  
  
I 栈对象B原先就持有C的引用，如若如此，C就必然已处于置灰状态（因为B已是黑色）  
  
II 栈对象B持有A的引用，通过A间接找到C. 然而这也是不可能的，因为倘若A能同时被另一个栈上的B引用到，那样A必然会升级到堆中，不再满足作为一个栈对象的前提；  
  
III B同栈内存在其他对象X可达C，此时从X出发，必然存在一个灰色对象，从其出发存在可达C的路线.  
  
综上，我们得以证明混合写屏障是能够胜任并发GC场景的解决方案，并且满足栈无须添加屏障的前提.  
  
   
# 4 源码导读展望  
  
理论的学习上更加生动、源码的学习则较为晦涩. 然而，个人秉持的观点是“原理需要被源码论证”. 因为理论是抽象的，且言语表达是带有主观性的，不同人传译分享后，难免存在偏颇和歧义. 再者，网上分享博客中人云亦云、断章取义的也不在少数. 因此，甄别是非真假的核心点就在于——深挖源码. 因为，代码是不会骗人的.  
  
怀揣着这个信念，下周我会带来垃圾回收源码走读相关的新作，此处我们先摘出走读代码的框架，大家如有兴趣，可以先作预习铺垫，这样下周食用效果更佳~  
## 4.1 源码文件位置  
  
<table><thead style="line-height: 1.75;background: rgba(0, 0, 0, 0.05);font-weight: bold;color: rgb(63, 63, 63);"><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;"><strong style="line-height: 1.75;color: rgb(15, 76, 129);">环节</strong></td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;"><strong style="line-height: 1.75;color: rgb(15, 76, 129);">文件位置</strong></td></tr></thead><tbody><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">主干流程</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime/mgc.go</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">调步策略</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime/mgcspacer.go</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">并发标记</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime/mgcmark.go</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">清扫流程</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime/msweep.go</td></tr></tbody></table>  

## 4.2 触发GC链路  
  
![](https://mmbiz.qpic.cn/mmbiz_png/3ic3aBqT2ibZsX03L7kZaOrjpArjV5TfmibRlicr60Gd4yYKiae0yAm7Jn4BRCrWwAZtiajX9DQLuYLFfcmrneheFfKA/640?wx_fmt=png "")  
  
I 定时触发GC  
  
<table><thead style="line-height: 1.75;background: rgba(0, 0, 0, 0.05);font-weight: bold;color: rgb(63, 63, 63);"><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;"><strong style="line-height: 1.75;color: rgb(15, 76, 129);">方法</strong></td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;"><strong style="line-height: 1.75;color: rgb(15, 76, 129);">文件</strong></td></tr></thead><tbody><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">init</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime/proc.go</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">forcegchelper</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime/proc.go</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">main</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime/proc.go</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">sysmon</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime/proc.go</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">injectglist</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime/proc.go</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">gcStart</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime/mgc.go</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">gcTrigger.test</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime/mgc.go</td></tr></tbody></table>  
  
   
  
II 对象分配触发  
  
![](https://mmbiz.qpic.cn/mmbiz_png/3ic3aBqT2ibZsX03L7kZaOrjpArjV5Tfmib5G3Fk8Ovic0mrdP711jjR5YmiaDqJQEJC1zwKibicBMSHEaibZrot4VLnkg/640?wx_fmt=png "")  
  
<table><thead style="line-height: 1.75;background: rgba(0, 0, 0, 0.05);font-weight: bold;color: rgb(63, 63, 63);"><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;"><strong style="line-height: 1.75;color: rgb(15, 76, 129);">方法</strong></td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;"><strong style="line-height: 1.75;color: rgb(15, 76, 129);">文件</strong></td></tr></thead><tbody><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">mallocgc</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime/malloc.go</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">gcTrigger.test</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime/mgc.go</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">gcStart</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime/mgc.go</td></tr></tbody></table>  
  
   
  
（2）标记准备  
  
![](https://mmbiz.qpic.cn/mmbiz_png/3ic3aBqT2ibZsX03L7kZaOrjpArjV5Tfmib4kv38ZwGwYcD84hOs9QsS4QO47puy7wuRPvia29z1nUrApQhXQdefkA/640?wx_fmt=png "")  
  
<table><thead style="line-height: 1.75;background: rgba(0, 0, 0, 0.05);font-weight: bold;color: rgb(63, 63, 63);"><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;"><strong style="line-height: 1.75;color: rgb(15, 76, 129);">方法</strong></td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;"><strong style="line-height: 1.75;color: rgb(15, 76, 129);">文件</strong></td></tr></thead><tbody><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">gcStart</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime/mgc.go</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">gcBgMarkStartWorkers</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime/mgc.go</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">gcBgMarkWorker</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime/mgc.go</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">stopTheWorldWithSema</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime/mgc.go</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">gcControllerState.startCycle</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime/mgcspacer.go</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">setGCPhase</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime/mgc.go</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">gcMarkRootPrepare</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime/mgc.go</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">gcMarkTinyAllocs</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime/mgc.go</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">startTheWorldWithSema</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime/mgc.go</td></tr></tbody></table>  
  
   
  
（3）并发标记  
  
![](https://mmbiz.qpic.cn/mmbiz_png/3ic3aBqT2ibZsX03L7kZaOrjpArjV5TfmibOf9GDp5ibNmJ51ibgFb0BD3JzR11CH2s7g3bL4upXqnMUuPNS0ztzPHA/640?wx_fmt=png "")  
  
I p 调度标记协程  
  
<table><thead style="line-height: 1.75;background: rgba(0, 0, 0, 0.05);font-weight: bold;color: rgb(63, 63, 63);"><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;"><strong style="line-height: 1.75;color: rgb(15, 76, 129);">方法</strong></td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;"><strong style="line-height: 1.75;color: rgb(15, 76, 129);">文件</strong></td></tr></thead><tbody><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">schedule</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime/proc.go</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">findRunnable</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime/proc.go</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">gcControllerState.findRunnableGCWorker</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime/mgcspacer.go</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">execute</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime/proc.go</td></tr></tbody></table>  
  
   
  
II 并发标记  
  
![](https://mmbiz.qpic.cn/mmbiz_png/3ic3aBqT2ibZsX03L7kZaOrjpArjV5TfmibgttXw8tTcia0gNegMZtibtql2rAsdICWYA8libAn8RN5IvGjoFcYbo9GA/640?wx_fmt=png "")  
  
<table><thead style="line-height: 1.75;background: rgba(0, 0, 0, 0.05);font-weight: bold;color: rgb(63, 63, 63);"><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;"><strong style="line-height: 1.75;color: rgb(15, 76, 129);">方法</strong></td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;"><strong style="line-height: 1.75;color: rgb(15, 76, 129);">文件</strong></td></tr></thead><tbody><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">gcBgMarkWorker</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime/mgc.go</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">gcDrain</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime/mgcmark.go</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">markroot</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime/mgcmark.go</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">scanobject</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime/mgcmark.go</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">greyobject</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime/mgcmark.go</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">markBits.setMarked</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime/mbitmap.go</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">gcWork.putFast/put</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime/mgcwork.go</td></tr></tbody></table>  
  
   
  
（4）标记清扫  
  
![](https://mmbiz.qpic.cn/mmbiz_png/3ic3aBqT2ibZsX03L7kZaOrjpArjV5TfmibpbkatUKpsGNiayOicGNPUF9zr5YksibkQRVzVJRNL8I4Qn7fD3vv2micWw/640?wx_fmt=png "")  
  
<table><thead style="line-height: 1.75;background: rgba(0, 0, 0, 0.05);font-weight: bold;color: rgb(63, 63, 63);"><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;"><strong style="line-height: 1.75;color: rgb(15, 76, 129);">方法</strong></td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;"><strong style="line-height: 1.75;color: rgb(15, 76, 129);">文件</strong></td></tr></thead><tbody><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">gcBgMarkWorker</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime/mgc.go</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">gcMarkDone</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime/mgc.go</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">stopTheWorldWithSema</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime/proc.go</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">gcMarkTermination</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime/mgc.go</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">gcSweep</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime/mgc.go</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">sweepone</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime/mgcsweep.go</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">sweepLocked.sweep</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime/mgcsweep.go</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">startTheWorldWithSema</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">runtime/proc.go</td></tr></tbody></table>  
  
  
