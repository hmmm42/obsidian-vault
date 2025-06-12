# Lab6 实验报告：中断处理机制实现

## 实验概述

Lab6在Lab4（CSR实现）和Lab5（异常处理）的基础上，进一步实现了RISC-V CPU的完整中断处理机制。本实验主要关注三种类型的中断及其处理流程：

### 实现的中断类型
- **Timer Interrupt (trint)**：定时器中断，用于时间片轮转和定时任务
- **Software Interrupt (swint)**：软件中断，用于处理器间通信和软件触发的中断
- **External Interrupt (exint)**：外部中断，用于处理来自外部设备的中断请求

### 核心实现模块
- **intprocesser.sv**：中断处理器，负责中断检测和优先级处理
- **ex_int_handler.sv**：异常中断处理单元，统一处理异常和中断
- **hazard.sv & stall.sv**：流水线危险控制，支持中断时的流水线刷新
- **core.sv**：核心处理器，集成中断处理功能

## 中断处理机制分析

### 1. 中断检测与处理器（intprocesser.sv）

中断处理器是Lab6的核心模块，负责检测三种类型的中断并判断是否应该响应。

#### 模块接口
```systemverilog
module intprocesser import common::*, pipedefs::*; (
    input u1 trint, swint, exint,    // 三种中断输入信号
    input csr_regs_t csr_regs,       // CSR寄存器状态
    output u1 any_interrupt          // 是否有中断需要处理
);
```

#### 中断使能检查逻辑
```systemverilog
always_comb begin : main_logic_of_intprocesser
    mstatus = csr_regs.mstatus;
    mie = csr_regs.mie;
    
    // 检查各类中断的使能状态
    twint_enabled = trint & mstatus.mie & mie[7];   // 定时器中断使能
    swint_enabled = swint & mstatus.mie & mie[3];   // 软件中断使能  
    exint_enabled = exint & mstatus.mie & mie[11];  // 外部中断使能
    
    // 任意中断使能则输出中断信号
    any_interrupt = twint_enabled | swint_enabled | exint_enabled;
end
```

#### 中断优先级与使能机制

1. **全局中断使能**：`mstatus.mie`位控制全局中断使能
2. **个别中断使能**：`mie`寄存器的特定位控制各类中断
   - `mie[7]`：定时器中断使能位
   - `mie[3]`：软件中断使能位  
   - `mie[11]`：外部中断使能位
3. **中断条件**：只有当中断信号有效且对应使能位都为1时，该中断才会被响应

### 2. 异常中断处理单元扩展（ex_int_handler.sv）

在Lab5异常处理的基础上，Lab6扩展了`ex_int_handler.sv`以支持中断处理。

#### 模块接口扩展
```systemverilog
module ex_int_handler import common::*, pipedefs::*; (
    input u1 clk, reset,
    input u1 trint, swint, exint,                    // 新增：中断输入信号
    input csr_regs_t csr_regs,
    input u64 pc, pcbranch,
    input u1 pcsrc,
    input u1 is_ecall, is_ebreak, is_unknown, is_mem_unaligned,  // 异常信号
    input u1 is_mret,
    output u2 privmode, privmode_next,
    output exception_info_t exception_info,
    output interruption_info_t interruption_info,    // 新增：中断信息输出
    output csr_regs_t special_csr_reg_vals,
    output u64 special_pc,
    output u1 special_pcsrc, special_csrsrc
);
```

#### 中断处理逻辑框架

在现有的ECALL、EBREAK、MRET处理基础上，添加了三种中断的处理分支：

```systemverilog
always_comb begin : ex_int_handler_main_logic
    special_csr_reg_vals = csr_regs;
    
    if(is_ecall) begin
        // ECALL异常处理（Lab5已实现）
        // 保存异常现场，设置mcause，跳转到异常处理程序
    end else if(is_mret) begin
        // MRET返回处理（Lab5已实现）
        // 恢复执行现场，返回到异常发生前的状态
    end else if(trint) begin
        // 定时器中断处理（Lab6新增）
        // TODO: 实现定时器中断处理逻辑
    end else if(swint) begin
        // 软件中断处理（Lab6新增）
        // TODO: 实现软件中断处理逻辑
    end else if(exint) begin
        // 外部中断处理（Lab6新增）
        // TODO: 实现外部中断处理逻辑
    end else begin
        // 默认情况：无异常或中断
        privmode_next = privmode;
        // 其他信号保持默认状态
    end
end
```

### 3. 中断处理的通用流程

根据RISC-V规范，中断处理应遵循以下通用流程：

#### 中断响应步骤
1. **保存当前状态**：
   - `mepc` ← 当前PC值
   - `mstatus.mpie` ← `mstatus.mie`（保存中断使能状态）
   - `mstatus.mpp` ← 当前特权级别
   
2. **设置中断环境**：
   - `mstatus.mie` ← 0（禁用中断）
   - 特权级别 ← M-mode
   - `mcause` ← 中断原因码
   
3. **跳转到中断处理程序**：
   - PC ← `mtvec`（中断向量表地址）

#### 中断原因码（mcause）
- 定时器中断：`mcause = 0x80000007`（最高位为1表示中断）
- 软件中断：`mcause = 0x80000003`
- 外部中断：`mcause = 0x8000000B`

### 4. 流水线中断处理（hazard.sv & stall.sv）

中断处理需要与流水线控制紧密配合，确保在中断响应时正确地刷新流水线。

#### 中断信号传递
```systemverilog
// core.sv中的中断处理器实例
intprocesser intprocesser(
    .trint(trint),
    .swint(swint), 
    .exint(exint),
    .csr_regs(csr_regs),
    .any_interrupt(any_interrupt)
);

// 传递给流水线控制单元
hazard hazard(
    .any_interrupt(any_interrupt),
    // 其他信号...
    .persist_flush_all(persist_flush_all)
);
```

#### 流水线刷新机制
```systemverilog
// stall.sv中的中断刷新逻辑
always_comb begin : begin_flush_all_logic
    begin_flush_all = 
        writeback_out.csr_wcontrol.wen;        // CSR写入
        // writeback_out.exception_info.valid |  // 异常发生
        // any_interrupt;                        // 中断发生（注释表示待实现）
end
```

当前实现中，中断的流水线刷新逻辑被注释，这表明完整的中断处理流水线刷新机制还需要进一步实现。

### 5. 中断与异常的区别

#### 异常（Exception）
- **同步事件**：由正在执行的指令引起
- **精确异常**：异常发生时，异常指令之前的所有指令都已完成，异常指令及之后的指令都未执行
- **处理时机**：在指令执行过程中检测到异常条件时立即处理
- **示例**：ECALL、EBREAK、非法指令、内存对齐错误

#### 中断（Interrupt）
- **异步事件**：由外部事件或定时器引起，与当前执行的指令无关
- **可延迟**：中断请求可以在指令边界处理，不需要立即响应
- **处理时机**：通常在指令执行完成后检查并处理
- **示例**：定时器中断、软件中断、外部设备中断

### 6. CSR寄存器在中断处理中的作用

#### mstatus寄存器
- `mie`位：全局中断使能控制
- `mpie`位：保存中断前的`mie`状态
- `mpp`字段：保存中断前的特权级别

#### mie寄存器（Machine Interrupt Enable）
- 位7：定时器中断使能（MTIE）
- 位3：软件中断使能（MSIE） 
- 位11：外部中断使能（MEIE）

#### mip寄存器（Machine Interrupt Pending）
- 位7：定时器中断挂起（MTIP）
- 位3：软件中断挂起（MSIP）
- 位11：外部中断挂起（MEIP）

#### mcause寄存器
- 最高位：区分中断（1）和异常（0）
- 低位：中断/异常的具体原因码

#### mtvec寄存器
- 存储中断向量表的基地址
- 中断发生时，PC跳转到此地址

#### mepc寄存器
- 保存中断发生时的PC值
- MRET指令执行时，PC恢复为此值

## 实现完整性分析

### 已实现的功能
1. **中断检测**：`intprocesser.sv`能够正确检测三种类型的中断
2. **中断使能控制**：支持通过CSR寄存器控制中断使能
3. **异常处理基础**：Lab5已建立完整的异常处理框架
4. **流水线集成**：中断信号已集成到流水线控制中

### 待完善的功能
1. **中断处理逻辑**：`ex_int_handler.sv`中三种中断的具体处理逻辑待实现
2. **流水线刷新**：中断时的完整流水线刷新机制待启用
3. **中断优先级**：多个中断同时发生时的优先级仲裁
4. **中断嵌套**：支持中断嵌套的完整机制

## 中断处理完整实现方案

基于当前的框架，完整的中断处理实现需要在`ex_int_handler.sv`中添加以下逻辑：

### 定时器中断处理
```systemverilog
else if(trint) begin
    special_csr_reg_vals.mepc = pc;
    special_csr_reg_vals.mcause = {1'b1, 63'd7};  // 中断标志位+定时器中断码
    special_csr_reg_vals.mstatus.mpie = csr_regs.mstatus.mie;
    special_csr_reg_vals.mstatus.mie = 0;
    special_csr_reg_vals.mstatus.mpp = privmode;
    privmode_next = 2'b11;  // 切换到M-mode
    special_pc = special_csr_reg_vals.mtvec;
    special_pcsrc = 1;
    special_csrsrc = 1;
end
```

### 软件中断处理
```systemverilog
else if(swint) begin
    special_csr_reg_vals.mepc = pc;
    special_csr_reg_vals.mcause = {1'b1, 63'd3};  // 中断标志位+软件中断码
    special_csr_reg_vals.mstatus.mpie = csr_regs.mstatus.mie;
    special_csr_reg_vals.mstatus.mie = 0;
    special_csr_reg_vals.mstatus.mpp = privmode;
    privmode_next = 2'b11;  // 切换到M-mode
    special_pc = special_csr_reg_vals.mtvec;
    special_pcsrc = 1;
    special_csrsrc = 1;
end
```

### 外部中断处理
```systemverilog
else if(exint) begin
    special_csr_reg_vals.mepc = pc;
    special_csr_reg_vals.mcause = {1'b1, 63'd11};  // 中断标志位+外部中断码
    special_csr_reg_vals.mstatus.mpie = csr_regs.mstatus.mie;
    special_csr_reg_vals.mstatus.mie = 0;
    special_csr_reg_vals.mstatus.mpp = privmode;
    privmode_next = 2'b11;  // 切换到M-mode
    special_pc = special_csr_reg_vals.mtvec;
    special_pcsrc = 1;
    special_csrsrc = 1;
end
```

## 测试验证方案

### 中断功能测试
1. **单一中断测试**：分别测试定时器、软件、外部中断的响应
2. **中断使能测试**：验证通过mie和mstatus控制中断使能的效果
3. **中断嵌套测试**：测试中断处理过程中再次发生中断的情况
4. **中断返回测试**：验证MRET指令正确恢复中断前的执行状态

### 流水线集成测试
1. **流水线刷新测试**：验证中断发生时流水线正确刷新
2. **数据一致性测试**：确保中断处理不会破坏程序数据的一致性
3. **性能测试**：测量中断响应延迟和处理开销
