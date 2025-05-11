- 邱俊博
- 23300240028

# 实验目的
在 lab1 的基础上, 实现以下指令:
ld sd lb lh lw lbu lhu lwu sb sh sw lui
内存访问延迟的周期数将会变为随机值, 需要根据`data_ok`信号来判断指令/数据访存请求是否完成.
# 实验过程
本次实验相比 lab1, 增添了读写内存的要求, 需要在 Memory 阶段加入对 `dreq` 和 `dresp` 信号的处理, 实现内存的读取和修改.

另外, lab2 中内存访问延迟的周期数是随机值, 需要根据`data_ok`信号来判断指令/数据访存请求是否完成.
## 转发
数据前递通过设计专用通路，将计算结果直接送到需要的地方，避免等待写回.
```verilog
     // EX/MEM -> EX前递
        if (regwriteM && (rs1E == dstM) && (dstM != '0))
            select_srcaE = aluoutM;  // 使用MEM阶段的ALU结果
        
        if (regwriteM && (rs2E == dstM) && (dstM != '0))
            select_srcbE = aluoutM;

        // MEM/WB -> EX前递
        else if (regwriteW && (rs1E == dstW) && (dstW != '0)) begin
            if (memtoregW)
                select_srcaE = readdataW;  // 使用内存读取的数据
            else
                select_srcaE = aluoutW;    // 使用WB阶段的ALU结果
        end
```
## 阻塞
当一个指令需要的数据还未准备好时，需要等待数据准备好后再执行.
```verilog
// 指令内存访问未就绪，暂停取指
assign stallF = ... | (ireq_valid && ~iresp_data_ok);

// 数据内存访问未就绪，暂停所有阶段
assign stallM = dreq_valid && ~dresp_data_ok;
```
# 测试结果
![image.png](https://raw.githubusercontent.com/hmmm42/Picbed/main/obsidian/pictures20250311170220765.png)

# 实验总结
本次实验需要实现流水线的核心机制, 包括数据前递和阻塞, 通过这两种机制, 实现了流水线的数据冒险和控制冒险的解决方案. 通过本次实验, 更加深入了解了流水线的实现细节, 对流水线的运行机制有了更深的理解.
