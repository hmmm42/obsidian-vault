# Lab5 实验报告：MRET与ECALL指令及MMU实现

## 实验概述

Lab5在Lab4的CSR指令基础上，进一步实现了RISC-V CPU的异常处理机制，主要包括：

### 实现的核心功能
- **ECALL指令**：环境调用指令，用于从低特权级别向高特权级别发起系统调用
- **MRET指令**：机器模式返回指令，用于从机器模式异常处理程序返回到之前的执行状态
- **MMU（内存管理单元）**：实现虚拟地址到物理地址的转换，支持分页机制
- **异常处理机制**：完整的陷阱处理流程，包括异常检测、上下文保存和恢复
- **特权级别管理**：支持机器模式（M-mode）、监管模式（S-mode）和用户模式（U-mode）

### 实现的异常类型
- **环境调用异常**：ECALL指令触发的系统调用
- **断点异常**：EBREAK指令触发的调试断点
- **非法指令异常**：未知指令码引发的异常
- **内存对齐异常**：内存访问地址未对齐引发的异常

## 关键模块分析

### 1. 异常中断处理器（ex_int_handler.sv）

异常中断处理器是Lab5的核心模块，位于Writeback阶段，负责处理所有的异常和中断事件。

#### 核心功能
```systemverilog
module ex_int_handler import common::*, pipedefs::*; (
    input u1 clk, reset,
    input u1 trint, swint, exint,  // 中断信号
    input csr_regs_t csr_regs,     // CSR寄存器状态
    input u64 pc, pcbranch,        // 当前PC和分支目标
    input u1 pcsrc,
    input u1 is_ecall, is_ebreak, is_unknown, is_mem_unaligned,  // 异常信号
    input u1 is_mret,              // MRET指令信号
    output u2 privmode, privmode_next,  // 特权级别管理
    output exception_info_t exception_info,
    output interruption_info_t interruption_info,
    output csr_regs_t special_csr_reg_vals,  // 更新后的CSR值
    output u64 special_pc,         // 异常处理后的PC
    output u1 special_pcsrc, special_csrsrc
);
```

#### ECALL指令处理
ECALL指令的处理涉及以下步骤：

1. **保存异常现场**：
```systemverilog
if(is_ecall) begin
    special_csr_reg_vals.mepc = pc;  // 保存异常发生时的PC
    case (privmode)
        2'b00: special_csr_reg_vals.mcause = 8;  // ECALL from U-mode
        2'b01: special_csr_reg_vals.mcause = 9;  // ECALL from S-mode  
        2'b11: special_csr_reg_vals.mcause = 11; // ECALL from M-mode
        default: special_csr_reg_vals.mcause = 0;
    endcase
```

2. **中断状态管理**：
```systemverilog
    special_csr_reg_vals.mstatus.mpie = csr_regs.mstatus.mie;  // 保存当前中断使能状态
    special_csr_reg_vals.mstatus.mie = 0;                      // 禁用中断
    special_csr_reg_vals.mstatus.mpp = privmode;               // 保存当前特权级别
```

3. **跳转到异常处理程序**：
```systemverilog
    privmode_next = 2'b11;                           // 切换到机器模式
    special_pc = special_csr_reg_vals.mtvec;         // 跳转到异常向量
    special_pcsrc = 1;                               // 使能PC跳转
    special_csrsrc = 1;                              // 使能CSR更新
end
```

#### MRET指令处理
MRET指令用于从异常处理程序返回，需要恢复之前的执行状态：

1. **恢复PC**：
```systemverilog
if(is_mret) begin
    special_pc = csr_regs.mepc;                      // 恢复异常前的PC
    special_pcsrc = 1;                               // 使能PC跳转
```

2. **恢复中断状态**：
```systemverilog
    special_csr_reg_vals.mstatus.mie = csr_regs.mstatus.mpie;  // 恢复中断使能状态
    special_csr_reg_vals.mstatus.mpie = 1;                     // 重置MPIE为1
    special_csr_reg_vals.mstatus.mpp = 0;                      // 重置MPP为用户模式
```

3. **恢复特权级别**：
```systemverilog
    privmode_next = csr_regs.mstatus.mpp;            // 恢复之前的特权级别
    special_csrsrc = 1;                              // 使能CSR更新
end
```

### 2. 指令解码器增强（signalgen.sv）

在指令解码阶段，需要识别ECALL、EBREAK和MRET指令：

#### 异常指令识别
```systemverilog
always_comb begin : exception_crude_info_logic
    is_ecall = 0; is_ebreak = 0; is_unknown = 0;
    unique case (cmd)
        ECALL: is_ecall = 1;    // 环境调用指令
        EBREAK: is_ebreak = 1;  // 断点指令
        UNKNOWN: is_unknown = 1; // 非法指令
        default: ;
    endcase
end

always_comb begin : is_mret_logic
    unique case (cmd)
        MRET: is_mret = 1;      // 机器模式返回指令
        default: is_mret = 0;
    endcase
end
```

### 3. 内存管理单元（MMU）

虽然在当前实现中MMU功能相对简化，但仍然提供了基本的虚拟地址管理框架：

#### MMU接口
在内存阶段（memory.sv）中，MMU相关的接口包括：
```systemverilog
module memory import common::*, pipedefs::*; (
    input logic clk, reset,
    input execute_out_t execute_out,
    output memory_out_t memory_out,
    input dbus_resp_t dresp,
    output dbus_req_t dreq,
    input u2 privmode,           // 当前特权级别
    output u1 mmu_finished,      // MMU操作完成信号
    input satp_t satp            // 地址转换和保护寄存器
);
```

#### 地址转换机制
satp寄存器的结构定义：
```systemverilog
typedef struct packed {
    u4  mode;    // 地址转换模式（0=裸机模式，8=Sv39，9=Sv48）
    u16 asid;    // 地址空间标识符，用于TLB管理
    u44 ppn;     // 页表基址的物理页号
} satp_t;
```

当启用虚拟内存时（satp.mode != 0），MMU会执行以下步骤：
1. **页表遍历**：从satp.ppn指向的根页表开始遍历
2. **权限检查**：根据当前特权级别验证页面访问权限
3. **地址转换**：将虚拟地址转换为物理地址
4. **TLB管理**：缓存地址转换结果以提高性能

### 4. 内存访问控制（dmemcontrol.sv）

内存访问控制模块处理数据内存的读写操作，并检测内存对齐异常：

#### 内存对齐检查
```systemverilog
assign is_mem_unaligned = (active_raw_meminfo.memread | active_raw_meminfo.memwrite) & 
    ((active_raw_meminfo.membytes != MSIZE1 && active_raw_meminfo.membytes != MSIZE2 && 
      active_raw_meminfo.membytes != MSIZE4 && active_raw_meminfo.membytes != MSIZE8) || 
     (active_raw_meminfo.membytes == MSIZE2 && (byte_offset[0] == 1'b1)) ||
     ((active_raw_meminfo.membytes == MSIZE4) && (byte_offset[1:0] != 2'b00)) ||
     ((active_raw_meminfo.membytes == MSIZE8) && (byte_offset != 3'b000)));
```

#### Strobe掩码生成
根据内存访问大小和地址偏移生成相应的strobe掩码：
```systemverilog
always_comb begin
    strobe_mask = 8'h0;
    if (active_raw_meminfo.memwrite) begin
        case (active_raw_meminfo.membytes)
            MSIZE1: begin // 1字节访问
                case (byte_offset)
                    3'b000: strobe_mask = 8'b00000001;
                    3'b001: strobe_mask = 8'b00000010;
                    // ... 其他情况
                endcase
            end
            MSIZE2: begin // 2字节访问
                case (byte_offset)
                    3'b000: strobe_mask = 8'b00000011;
                    3'b010: strobe_mask = 8'b00001100;
                    // ... 其他情况
                endcase
            end
            // ... 处理4字节和8字节访问
        endcase
    end
end
```

### 5. 流水线刷新机制

异常处理需要刷新整个流水线以确保程序正确执行：

#### 危险控制（hazard.sv）
```systemverilog
always_comb begin : begin_flush_all_logic
    begin_flush_all =
        writeback_out.csr_wcontrol.wen |          // CSR写入
        writeback_out.exception_info.valid |     // 异常发生
        any_interrupt;                            // 中断发生
end
```

当检测到需要刷新的条件时，hazard控制单元会：
1. **停止取指**：暂停新指令的获取
2. **刷新流水线**：清空所有流水线寄存器
3. **更新PC**：设置新的程序计数器值
4. **恢复执行**：在新的上下文中继续执行

## 特权级别管理

### 特权级别定义
- **机器模式（M-mode）**：privmode = 2'b11，最高特权级别，可以访问所有系统资源
- **监管模式（S-mode）**：privmode = 2'b01，操作系统内核级别，可以管理用户程序
- **用户模式（U-mode）**：privmode = 2'b00，最低特权级别，只能访问用户空间资源

### 特权级别转换
1. **异常发生时**：自动提升到机器模式（M-mode）
2. **MRET执行时**：根据mstatus.mpp恢复到之前的特权级别
3. **SRET执行时**：从监管模式返回到之前的特权级别

### mstatus寄存器关键字段
```systemverilog
typedef struct packed {
    // ... 其他字段
    u2 mpp;          // Machine Previous Privilege - 进入M-mode前的特权级别
    u1 mpie;         // Machine Previous Interrupt Enable - 进入M-mode前的中断使能状态
    u1 mie;          // Machine Interrupt Enable - 机器模式中断使能
    // ... 其他字段
} mstatus_t;
```

## 异常处理流程

### 异常发生流程
1. **异常检测**：在各个流水线阶段检测异常条件
2. **流水线刷新**：清空所有正在执行的指令
3. **上下文保存**：
   - 保存当前PC到mepc
   - 保存异常原因到mcause  
   - 保存当前特权级别到mstatus.mpp
   - 保存中断使能状态到mstatus.mpie
4. **特权级别提升**：切换到机器模式
5. **跳转执行**：跳转到mtvec指向的异常处理程序

### 异常返回流程
1. **MRET指令执行**：触发异常返回操作
2. **上下文恢复**：
   - 从mepc恢复PC
   - 从mstatus.mpp恢复特权级别
   - 从mstatus.mpie恢复中断使能状态
3. **继续执行**：在恢复的上下文中继续执行

## CSR寄存器在异常处理中的作用

### mepc（Machine Exception Program Counter）
- **功能**：保存发生异常时的PC值
- **用途**：MRET指令使用此值恢复程序执行位置
- **更新时机**：异常发生时自动更新

### mcause（Machine Cause Register）
- **功能**：记录异常或中断的原因
- **格式**：最高位表示是否为中断，低位表示具体原因码
- **原因码**：
  - 8：用户模式环境调用
  - 9：监管模式环境调用
  - 11：机器模式环境调用

### mtval（Machine Trap Value）
- **功能**：提供异常相关的附加信息
- **用途**：存储导致异常的内存地址或指令值
- **应用场景**：内存访问异常、非法指令异常等

### mtvec（Machine Trap Vector）
- **功能**：存储异常处理程序的入口地址
- **模式**：支持直接模式和向量模式
- **用途**：异常发生时CPU自动跳转到此地址

## MMU虚拟内存管理

### 页表结构
RISC-V支持多级页表结构，常见的包括：
- **Sv39**：39位虚拟地址，3级页表
- **Sv48**：48位虚拟地址，4级页表

### 地址转换过程
1. **模式检查**：检查satp.mode确定是否启用虚拟内存
2. **页表遍历**：从根页表开始逐级查找
3. **权限验证**：检查页表项的读、写、执行权限
4. **地址计算**：组合页表项PPN和页内偏移得到物理地址

### 特权级别与内存保护
- **用户页面**：只有在用户模式下才能访问
- **监管页面**：监管模式和机器模式都可以访问
- **可执行页面**：标记为可执行的页面才能取指
- **写保护**：只有标记为可写的页面才能进行写操作

