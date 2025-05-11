# Lab1 寻找样本 DNA 序列中的重复片段

- 邱俊博
- 23300240028
- 仓库地址：[https://github.com/hmmm42/DNA-Sequence-Alignments](https://github.com/hmmm42/DNA-Sequence-Alignments)
---

## 一、核心算法设计

本算法利用后缀自动机（SAM）实现生物序列的高效匹配与重复结构分析，主要流程分为自动机构建、匹配预计算及重复检测三个阶段。以下为各模块的详细描述：

---

### 1. 后缀自动机构造模块
**目标**：为参考序列及其反向互补序列建立高效的子串匹配结构。

**伪代码实现**：
```
FUNCTION CONSTRUCT-SAM(sequence):
    automaton = {states: [init_state], last: 0, size: 1}
    FOR char IN sequence:
        APPEND-STATE(automaton, char)
    RETURN automaton

PROCEDURE APPEND-STATE(automaton, char):
    prev = automaton.last
    new_state_id = automaton.size
    ADD_STATE(automaton, {length: automaton.states[prev].length + 1})
    
    WHILE prev != -1 AND char NOT IN automaton.states[prev].trans:
        automaton.states[prev].trans[char] = new_state_id
        prev = automaton.states[prev].suffix_link
    
    IF prev == -1:
        automaton.states[new_state_id].suffix_link = 0
    ELSE:
        exist_state = automaton.states[prev].trans[char]
        IF automaton.states[exist_state].length == automaton.states[prev].length + 1:
            automaton.states[new_state_id].suffix_link = exist_state
        ELSE:
            clone_state = CLONE-STATE(automaton, exist_state)
            automaton.states[new_state_id].suffix_link = clone_state
            UPDATE-TRANSITIONS(automaton, prev, char, clone_state)
    
    automaton.last = new_state_id
```

**复杂度分析**：  
• 时间：构造单SAM需O(n)，总参考序列构造为O(r)
• 空间：存储状态与转移关系，空间消耗O(r)

---

### 2. 最长匹配预计算模块
**目标**：为查询序列的每个位置计算与参考序列的正向/反向最长匹配。

**伪代码实现**：
```
FUNCTION CALC-MAX-MATCH(sam, query, start_pos):
    current_node = 0
    match_len = 0
    
    FOR j FROM start_pos TO LEN(query)-1:
        current_char = query[j]
        IF current_char IN sam.states[current_node].trans:
            current_node = sam.states[current_node].trans[current_char]
            match_len += 1
        ELSE:
            BREAK
    RETURN match_len
```

**执行流程**：
1. 对查询序列各位置i，分别计算：
   • 正向匹配长度len_forward = CALC-MAX-MATCH(sam_ref, query, i)
   • 反向匹配长度len_revcom = CALC-MAX-MATCH(sam_inv, query, i)
2. 记录元组(max_len, is_revcom)，其中：
   • max_len = max(len_forward, len_revcom)
   • is_revcom = (len_revcom > len_forward) or (len_revcom == len_forward > 0)

**复杂度分析**：  
• 时间：O(q²)（需对每个位置进行线性扫描）
• 空间：O(q)（存储预计算结果）

---

### 3. 重复区域识别模块
**目标**：基于预计算数据，检测连续重复结构并定位参考序列坐标。

**伪代码实现**：
```
ALGORITHM analyzeDuplicates(query, ref)
    # 输入: query序列, ref参考序列
    # 输出: 重复片段列表
    
    inv_ref ← REVERSE_COMPLEMENT(ref)  # 反向互补处理[1,3](@ref)
    
    # 构建后缀自动机
    sam_ref ← BUILD_SAM(ref)           # 参考序列SAM[1](@ref)
    sam_inv ← BUILD_SAM(inv_ref)       # 反向互补SAM[1](@ref)
    
    # 预计算最大匹配信息
    match_data ← ARRAY[query.length]
    FOR pos FROM 0 TO query.length-1:
        len_ref ← FIND_MAX_MATCH(sam_ref, query, pos)
        len_inv ← FIND_MAX_MATCH(sam_inv, query, pos)
        
        # 选择最优匹配
        is_inv ← (len_inv > len_ref) OR (len_inv = len_ref AND len_inv > 0)
        best_len ← MAX(len_ref, len_inv)
        match_data[pos] ← (best_len, is_inv)
    
    # 重复片段检测
    duplicates ← EMPTY_LIST
    pos ← 0
    WHILE pos < query.length:
        (unit_len, is_inv) ← match_data[pos]
        IF unit_len = 0:
            pos ← pos + 1
            CONTINUE
        
        # 提取重复单元
        repeat_unit ← query[pos : pos+unit_len]
        count ← 1
        next_pos ← pos + unit_len
        
        # 验证连续重复
        WHILE next_pos + unit_len ≤ query.length:
            current_match ← match_data[next_pos]
            IF current_match.max_length < unit_len OR 
               current_match.is_inv ≠ is_inv OR
               query[next_pos : next_pos+unit_len] ≠ repeat_unit:
                BREAK
            count ← count + 1
            next_pos ← next_pos + unit_len
        
        # 定位参考序列坐标
        IF is_inv:
            ref_substr ← REVERSE_COMPLEMENT(repeat_unit)
        ELSE:
            ref_substr ← repeat_unit
        ref_start ← INDEX_OF(ref, ref_substr)  # 首次匹配位置
        
        # 记录结果
        duplicates.APPEND( (pos, ref_start, unit_len, count, is_inv) )
        pos ← next_pos
    
    RETURN duplicates
```

**关键操作**：
• 反向互补处理：`REVERSE-COMPLEMENT`函数实现碱基配对转换
• 参考序列定位：使用字符串搜索算法确定首次出现位置

**复杂度分析**：  
• 时间：O(q² + qr)（重复检测与参考定位）
• 空间：O(d)（存储检测结果）

---

## 二、复杂度总览
• **时间复杂度**：  
  SAM构造O(r) + 匹配预计算O(q²) + 重复检测O(qr + q²) → **总计O(q² + r)**
  
• **空间复杂度**：  
  SAM存储O(r) + 预计算结果O(q) + 结果集O(d) → **总计O(r + q)**

---

## 三、实验结果示例
通过可视化工具生成如下重复区域检测结果：

| Pos in Ref | Repeat Size | Repeat Count | Inverse |
| ---------- | ----------- | ------------ | ------- |
| 0          | 402         | 1            | Yes     |
| 352        | 50          | 3            | Yes     |
| 352        | 48          | 1            | No      |
| 330        | 70          | 3            | Yes     |
| 298        | 102         | 1            | No      |
| 400        | 400         | 1            | Yes     |

运行结果截图：
![image.png](https://raw.githubusercontent.com/hmmm42/Picbed/main/obsidian/pictures20250325231736796.png)

---

该方案在保证线性空间复杂度的前提下，通过后缀自动机显著提升了长序列处理的效率，有效解决了寻找样本 DNA 序列中的重复片段的问题。
