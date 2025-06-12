# Lab4 实验报告：CSR指令与寄存器实现

## 实验概述

本实验的目标是实现RISC-V的CSR（Control and Status Register）指令和相关寄存器，包括：

### 实现的指令
- **CSRRW**：CSR Read and Write
- **CSRRS**：CSR Read and Set  
- **CSRRC**：CSR Read and Clear
- **CSRRWI**：CSR Read and Write Immediate
- **CSRRSI**：CSR Read and Set Immediate
- **CSRRCI**：CSR Read and Clear Immediate

### 实现的CSR寄存器
- **mstatus**：机器状态寄存器
- **mtvec**：机器陷阱向量基址寄存器
- **mip**：机器中断挂起寄存器
- **mie**：机器中断使能寄存器
- **mscratch**：机器暂存寄存器
- **mcause**：机器陷阱原因寄存器
- **mtval**：机器陷阱值寄存器
- **mepc**：机器异常程序计数器
- **mcycle**：机器周期计数器
- **mhartid**：硬件线程ID寄存器
- **satp**：地址转换和保护寄存器

## 实现分析

### 1. CSR指令实现

根据dywsy21的实现，CSR指令在以下模块中处理：

#### 指令解码（cmddecoder.sv）
```systemverilog
7'b1110011:
    unique case (funct12)
        12'b000000000000: cmd = ECALL;
        12'b000000000001: cmd = EBREAK;
        12'b001100000010: cmd = MRET;
        default: cmd = UNKNOWN;
    endcase
    3'b001: cmd = CSRRW;
    3'b101: cmd = CSRRWI;
    3'b011: cmd = CSRRC;
    3'b111: cmd = CSRRCI;
    3'b010: cmd = CSRRS;
    3'b110: cmd = CSRRSI;
```

#### ALU处理（alu.sv）
```systemverilog
ALU_CSRRW: aluout = srca;           // 直接写入rs1值
ALU_CSRRWI: aluout = srca;          // 直接写入立即数
ALU_CSRRC: aluout = srcb & ~srca;   // 清除指定位
ALU_CSRRCI: aluout = srcb & ~srca;  // 清除指定位（立即数）
ALU_CSRRS: aluout = srcb | srca;    // 设置指定位
ALU_CSRRSI: aluout = srcb | srca;   // 设置指定位（立即数）
```

### 2. CSR寄存器实现

#### CSR结构定义（pipedefs.sv）
```systemverilog
typedef struct packed {
    mstatus_t mstatus;
    csr_val_t mepc;
    csr_val_t mtvec;
    mcause_t  mcause;
    csr_val_t mtval;
    csr_val_t mcycle;
    csr_val_t mscratch;
    csr_val_t mip;
    csr_val_t mie;
    satp_t    satp;
    csr_val_t mhartid;
} csr_regs_t;
```

#### CSR读写逻辑（csr.sv）
```systemverilog
// 读取CSR
always_comb begin : read_csr
    case (input_csr_addr)
        CSR_MTVEC: csr_val = csr_regs.mtvec;
        CSR_MEPC: csr_val = csr_regs.mepc;
        CSR_MCAUSE: csr_val = csr_regs.mcause;
        CSR_MIP: csr_val = csr_regs.mip;
        CSR_MIE: csr_val = csr_regs.mie;
        CSR_MSCRATCH: csr_val = csr_regs.mscratch;
        CSR_MTVAL: csr_val = csr_regs.mtval;
        CSR_MSTATUS: csr_val = csr_regs.mstatus;
        CSR_MCYCLE: csr_val = csr_regs.mcycle;
        CSR_SATP: csr_val = csr_regs.satp;
        default: csr_val = 0;
    endcase
end

// 写入CSR
always_comb begin : gen_next_for_difftest
    csr_regs_nxt = csr_regs;
    if(csr_wcontrol.wen | special_csrsrc) begin
        if(special_csrsrc) begin
            csr_regs_nxt = special_csr_reg_vals;
        end else begin
            case (csr_wcontrol.csr_addr)
                CSR_MTVEC: csr_regs_nxt.mtvec = csr_wcontrol.csr_val & MTVEC_MASK;
                CSR_MEPC: csr_regs_nxt.mepc = csr_wcontrol.csr_val;
                CSR_MCAUSE: csr_regs_nxt.mcause = csr_wcontrol.csr_val;
                CSR_MIP: csr_regs_nxt.mip = csr_wcontrol.csr_val & MIP_MASK;
                CSR_MIE: csr_regs_nxt.mie = csr_wcontrol.csr_val;
                CSR_MSCRATCH: csr_regs_nxt.mscratch = csr_wcontrol.csr_val;
                CSR_MTVAL: csr_regs_nxt.mtval = csr_wcontrol.csr_val;
                CSR_MSTATUS: begin
                    csr_regs_nxt.mstatus = csr_wcontrol.csr_val & MSTATUS_MASK;
                end
                CSR_MCYCLE: csr_regs_nxt.mcycle = csr_wcontrol.csr_val;
                CSR_SATP: csr_regs_nxt.satp = csr_wcontrol.csr_val;
            endcase
        end
    end
end
```

### 3. 特殊CSR寄存器处理

#### mcycle寄存器
```systemverilog
always_ff @( posedge clk, posedge reset ) begin : write_csr
    if(reset) begin
        csr_regs <= 0;
        csr_regs.mstatus.mpie <= 1;
        csr_regs.satp.mode <= 8; // sv39
    end else begin
        csr_regs <= csr_regs_nxt;
        csr_regs.mcycle <= csr_regs.mcycle + 1; // 每周期递增
    end
end
```

#### mhartid寄存器
- 固定设置为0（单核系统）
- 在core.sv中连接到DifftestCSRState的coreid

### 4. CSR Mask机制

部分CSR寄存器的位不是完全可写的，需要使用mask：

```systemverilog
parameter u64 MSTATUS_MASK = 64'h7e79bb;
parameter u64 SSTATUS_MASK = 64'h800000030001e000;
parameter u64 MIP_MASK = 64'h333;
parameter u64 MTVEC_MASK = ~(64'h2);
```

### 5. sstatus寄存器处理

sstatus是mstatus的子集，在DifftestCSRState中连接：
```systemverilog
.sstatus(csr_regs.mstatus & SSTATUS_MASK)
```

### 6. 流水线刷新机制

CSR指令会导致流水线刷新，在hazard控制中实现：

```systemverilog
always_comb begin : begin_flush_all_logic
    begin_flush_all = writeback_out.csr_wcontrol.wen; // CSR写入导致刷新
end
```

### 7. DifftestCSRState连接

在core.sv中连接所有CSR寄存器到difftest接口：

```systemverilog
DifftestCSRState DifftestCSRState(
    .clock(clk),
    .coreid(csr_regs.mhartid[7:0]),
    .priviledgeMode(privmode),
    .mstatus(csr_regs.mstatus),
    .sstatus(csr_regs.mstatus & SSTATUS_MASK),
    .mepc(csr_regs.mepc),
    .sepc(0),
    .mtval(csr_regs.mtval),
    .stval(0),
    .mtvec(csr_regs.mtvec),
    .stvec(0),
    .mcause(csr_regs.mcause),
    .scause(0),
    .satp(csr_regs.satp),
    .mip(csr_regs.mip),
    .mie(csr_regs.mie),
    .mscratch(csr_regs.mscratch),
    .sscratch(0),
    .mideleg(0),
    .medeleg(0)
);
```

## 各CSR寄存器作用说明（Bonus）

### mstatus (Machine Status Register)
- 保存机器模式的处理器状态
- 包含中断使能位（MIE）、之前的中断使能位（MPIE）
- 保存之前的特权级别（MPP）
- 控制虚拟内存、用户内存访问等

### mtvec (Machine Trap Vector)
- 存储机器模式陷阱处理程序的基址
- 支持直接模式和向量模式

### mip (Machine Interrupt Pending)
- 显示当前挂起的中断
- 只有特定位可读写（使用MIP_MASK）

### mie (Machine Interrupt Enable)
- 控制各种中断的使能
- 与mip配合工作确定哪些中断被处理

### mscratch (Machine Scratch Register)
- 机器模式的暂存寄存器
- 通常用于保存指向机器模式上下文的指针

### mcause (Machine Cause Register)
- 记录导致陷阱的原因
- 最高位指示是中断（1）还是异常（0）

### mtval (Machine Trap Value)
- 提供关于陷阱的额外信息
- 对于地址未对齐异常，包含出错的地址

### mepc (Machine Exception Program Counter)
- 保存发生异常时的PC值
- MRET指令会跳转到此地址

### mcycle (Machine Cycle Counter)
- 计算机器运行的周期数
- 每个时钟周期递增1
- 可以被软件读取和写入

### mhartid (Machine Hardware Thread ID)
- 标识当前硬件线程
- 在多核系统中区分不同核心
- 本实验中固定为0

### satp (Supervisor Address Translation and Protection)
- 控制虚拟内存地址转换
- 包含页表基址和地址转换模式

## 流水线刷新的必要性（Bonus思考）

CSR指令必须刷新流水线的原因：

1. **状态一致性**：CSR的修改可能影响后续指令的执行行为，如中断使能状态改变
2. **权限检查**：特权级别的改变需要重新验证后续指令的执行权限  
3. **内存映射**：satp寄存器的修改会影响虚拟地址到物理地址的转换
4. **中断处理**：mie、mip等寄存器的修改会立即影响中断的处理逻辑
5. **陷阱向量**：mtvec的修改需要确保异常处理跳转到正确的地址

