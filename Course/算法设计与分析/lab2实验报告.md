## 实验报告：复杂DNA序列比对算法
- 邱俊博
- 23300240028
- 仓库地址：[https://github.com/hmmm42/DNA-Sequence-Alignments](https://github.com/hmmm42/DNA-Sequence-Alignments)
### 1. 算法概述

本算法旨在实现复杂DNA序列（查询序列 Query 和参考序列 Reference）的比对。它基于“种子-延伸-链接”（Seed-Extend-Chain）的策略，并结合图论方法来寻找最优的匹配路径。主要步骤包括：

1. **参数自适应**：根据输入序列的长度和GC含量，动态调整k-mer大小、最小匹配长度、错误容忍度等参数。
2. **锚点发现（Anchor Finding）**：
    - **k-mer匹配**：在Query和Reference之间快速查找长度为k的完全匹配的短序列（k-mers）作为初始“种子”。
    - **锚点延伸（Anchor Extension）**：从这些种子出发，向两端延伸匹配，允许一定的错配（mismatches）和插入缺失（indels），形成更长的锚点区域（anchors）。同时会匹配正向链和反向互补链。
3. **锚点过滤（Anchor Filtering）**：根据锚点的得分、长度、以及它们之间的重叠程度，过滤掉低质量或冗余的锚点。
4. **片段图构建与路径选择（Chaining）**：
    - 将筛选后的锚点视为图中的节点。
    - 如果两个锚点在Query和Reference上都保持一致的顺序且不冲突（或有合理的间隙），则在它们之间建立有向边。边的权重可以基于锚点的得分。
    - 算法的目标是在这个有向无环图（DAG）中找到一条总权重最大的路径，这条路径代表了一组连续且兼容的匹配片段。
5. **片段合并与覆盖**：
    - **邻近片段合并**：将路径上相邻且间隙较小的匹配片段进行合并。
    - **确保完全覆盖**：检查Query序列中未被匹配的区域，并尝试对这些区域进行二次匹配（可能使用更宽松的参数或分块策略），或者进行简单的填充以保证Query的完整性。
    - **最终合并与重叠解决**：进行最后的片段合并和重叠区域处理。

---

### 2. 算法伪代码

#### 2.1 主比对函数 (`FindAlignment`)


```
FUNCTION FindAlignment(query, reference):
    // 1. 参数自适应
    ADAPT parameters (k_values, min_match_len, max_errors, stride) BASED ON len(query), len(reference), GC_content(query)

    all_forward_anchors = []
    all_reverse_anchors = []

    // 2. 初始锚点发现 (针对不同k值)
    FOR k IN k_values_to_try:
        current_stride = CALCULATE_STRIDE(k, sequence_length_class) // 根据k和序列长度类别调整步长
        
        // 2a. 查找正向锚点
        new_f_anchors = FindAnchors(query, reference, k, current_min_match_len, current_stride, current_max_errors)
        APPEND new_f_anchors TO all_forward_anchors
        
        // 2b. 查找反向互补锚点
        new_r_anchors = FindReverseAnchors(query, reference, k, current_min_match_len, current_stride, current_max_errors)
        APPEND new_r_anchors TO all_reverse_anchors

    // 3. 锚点过滤
    filtered_forward_anchors = FilterAnchors(all_forward_anchors, overlap_threshold_adjusted_by_GC)
    filtered_reverse_anchors = FilterAnchors(all_reverse_anchors, overlap_threshold_adjusted_by_GC)

    // 4. 通过图构建和最长路径寻找来链接锚点
    forward_chained_segments = ChainAnchorsUsingGraph(filtered_forward_anchors)
    reverse_chained_segments = ChainAnchorsUsingGraph(filtered_reverse_anchors)

    // 5. 合并与后处理
    combined_segments = forward_chained_segments + reverse_chained_segments
    initial_segments = RESOLVE_OVERLAPS_AND_SORT(combined_segments) // 优先保留更长的片段

    merged_segments_pass1 = MergeAdjacentSegments(initial_segments, ADJACENT_MERGE_MAX_GAP)
    
    // 6. 确保查询序列的完整覆盖
    segments_after_coverage = EnsureCompleteCoverage(query, reference, merged_segments_pass1)
    
    merged_segments_pass2 = MergeAdjacentSegments(segments_after_coverage, FINAL_MERGE_MAX_GAP)
    final_segments = RESOLVE_OVERLAPS(merged_segments_pass2) // 最终重叠解决

    // 7. 输出准备
    CLAMP_SEGMENT_BOUNDARIES(final_segments, len(query), len(reference))
    SORT final_segments FOR consistent output
    RETURN final_segments
```

#### 2.2 锚点发现 (`FindAnchors`)


```
FUNCTION FindAnchors(query, ref, k, min_match_len, stride, max_errors):
    // 1. 查找精确k-mer匹配
    exact_kmer_matches = FindExactKmerMatches(query, ref, k) 
    
    anchors = []
    processed_kmer_starts = new Set() // 用于记录已处理的k-mer起始，避免冗余延伸

    // 2. 延伸k-mer匹配
    FOR i, kmer_match IN enumerate(exact_kmer_matches):
        IF (i % stride != 0 AND (kmer_match.query_pos, kmer_match.ref_pos) IN processed_kmer_starts):
            CONTINUE // 根据步长和已处理标记跳过一些k-mer
        
        // 2a. 延伸匹配
        extended_anchor = ExtendKmerMatch(query, ref, kmer_match.query_pos, kmer_match.ref_pos, k, min_match_len, max_errors)
        
        IF extended_anchor IS NOT NULL:
            ADD extended_anchor TO anchors
            // 标记此锚点覆盖的关键k-mer起始位置为已处理
            MARK_PROCESSED(extended_anchor, processed_kmer_starts, query, ref) 
    
    // 3. 过滤重叠锚点 (基于得分排序后，移除重叠率过高的低分锚点)
    filtered_anchors = FilterOverlappingAnchors(anchors, current_overlap_threshold) 
    
    SORT filtered_anchors BY query_start_position
    RETURN filtered_anchors
```

#### 2.3 k-mer匹配延伸 (`ExtendKmerMatch`)


```
FUNCTION ExtendKmerMatch(query, ref, q_kmer_start, r_kmer_start, k_len, min_total_len, max_extend_errors):
    // 初始化延伸起点和终点 (基于k-mer)
    q_fwd_idx = q_kmer_start + k_len
    r_fwd_idx = r_kmer_start + k_len
    num_matches = k_len
    current_fwd_errors = 0

    // 向前延伸
    WHILE q_fwd_idx < len(query) AND r_fwd_idx < len(ref) AND current_fwd_errors <= max_extend_errors:
        IF query[q_fwd_idx] == ref[r_fwd_idx]: // 匹配
            INCREMENT q_fwd_idx, r_fwd_idx, num_matches
        ELSE: // 不匹配，尝试处理indel或计为错配
            indel_found_fwd = TRY_HANDLE_INDEL(query, ref, q_fwd_idx, r_fwd_idx, 1..2) // 尝试1-2bp的indel
            IF indel_found_fwd:
                UPDATE q_fwd_idx, r_fwd_idx, num_matches BASED ON indel
                INCREMENT current_fwd_errors
            ELSE: // 错配
                INCREMENT q_fwd_idx, r_fwd_idx
                INCREMENT current_fwd_errors
    
    // 初始化向后延伸的起点
    q_bwd_idx = q_kmer_start - 1
    r_bwd_idx = r_kmer_start - 1
    current_bwd_errors = 0 // Python代码中向后延伸时重置了错误计数

    // 向后延伸 (逻辑与向前延伸类似)
    WHILE q_bwd_idx >= 0 AND r_bwd_idx >= 0 AND current_bwd_errors <= max_extend_errors:
        // ... 类似向前延伸的逻辑 ...

    // 最终确定的锚点边界
    final_q_start_incl = q_bwd_idx + 1
    final_r_start_incl = r_bwd_idx + 1
    final_q_end_incl = q_fwd_idx - 1
    final_r_end_incl = r_fwd_idx - 1
    
    current_match_length = final_q_end_incl - final_q_start_incl + 1

    // 计算特征 (identity, score)
    identity = CALCULATE_IDENTITY(num_matches, current_match_length) 
    // (Python代码中包含一个基于上下文调整identity的逻辑)
    
    IF current_match_length >= min_total_len AND identity >= MIN_IDENTITY_THRESHOLD:
        // Python代码中计分时使用的错误数是向后延伸的错误数(current_bwd_errors)
        score = CALCULATE_SCORE(current_match_length, identity, current_bwd_errors) 
        RETURN new Anchor(final_q_start_incl, final_q_end_incl, final_r_start_incl, final_r_end_incl, score, identity)
    ELSE:
        RETURN NULL
```

#### 2.4 锚点链接 (`ChainAnchorsUsingGraph`)


```
FUNCTION ChainAnchorsUsingGraph(anchor_list):
    IF anchor_list IS EMPTY: RETURN []
    
    // anchor_list 应已按 query_start 排序
    num_anchors = len(anchor_list)
    
    // 构建图: 节点为锚点索引 (0 to num_anchors-1), 外加源点 (-1) 和汇点 (num_anchors)
    // 边 (u, v) 存在如果锚点u和锚点v兼容 (例如 v在u之后且不冲突)
    // 边的权重是目标锚点v的得分
    segment_graph = BuildSegmentGraph(anchor_list, num_anchors) 

    // 在图中寻找最大权重路径 (动态规划)
    optimal_path_indices = FindMaximumWeightPath(segment_graph, num_anchors) 
    
    chained_segments_result = []
    FOR index IN optimal_path_indices:
        ADD anchor_list[index] (转换为Segment格式) TO chained_segments_result
    RETURN chained_segments_result
```

#### 2.5 确保完全覆盖 (`EnsureCompleteCoverage`)

```
FUNCTION EnsureCompleteCoverage(query, ref, initial_segments_list):
    SORT initial_segments_list BY query_start // 确保有序
    uncovered_query_regions = FindUncoveredRegions(query, initial_segments_list)
    
    IF uncovered_query_regions IS EMPTY: RETURN initial_segments_list

    all_segments_collected = copy(initial_segments_list)
    FOR EACH region (q_start, q_end) IN uncovered_query_regions:
        IF region_length < THRESHOLD: CONTINUE
        
        current_query_substring = query[q_start : q_end+1]
        
        // 尝试用不同策略匹配该未覆盖区域
        IF region_length > LARGE_REGION_SIZE_THRESHOLD:
            // 大区域：分块匹配，尝试多种k值
            matches_for_region = FindMatchesInLargeRegion(current_query_substring, ref, ...) 
        ELSE:
            // 小区域：直接匹配，可能用特定k值
            matches_for_region = FindMatchesInRegion(current_query_substring, ref, ...)

        IF matches_for_region IS NOT EMPTY:
            SORT matches_for_region BY score (descending)
            FOR EACH match IN matches_for_region:
                CONVERT match_coordinates TO absolute query coordinates
                // 添加到all_segments_collected，需注意避免与已有片段严重重叠
                // (Python代码中有一个简单的重叠检查逻辑)
                ADD non_overlapping_match_segment TO all_segments_collected 
        ELSE: // 未找到匹配，使用回退策略 (Fallback)
            IF region_length > MAX_FALLBACK_SEGMENT_SIZE:
                DIVIDE region into smaller chunks (e.g., SMALL_SEGMENT_LENGTH)
                FOR EACH chunk:
                    FIND best approximate match for chunk in ref (e.g., by sampling ref positions)
                    ADD this_fallback_segment TO all_segments_collected
            ELSE:
                ADD single fallback_segment for the entire region TO all_segments_collected
    
    // 对所有收集到的片段 (原始的 + 新补充的) 进行排序和重叠解决
    SORT all_segments_collected BY query_start
    // Python代码中有一个特殊的重叠解决逻辑，优先保留原始片段，其次是更长的片段
    resolved_segments_list = RESOLVE_OVERLAPS_WITH_PREFERENCE(all_segments_collected, initial_segments_list) 
    
    // 最终检查并填充仍未覆盖的极小区域
    final_uncovered_gaps = FindUncoveredRegions(query, resolved_segments_list)
    IF final_uncovered_gaps IS NOT EMPTY:
        FOR EACH gap (s, e) IN final_uncovered_gaps:
            ADD simple placeholder_segment for gap TO resolved_segments_list
        resolved_segments_list = RESOLVE_OVERLAPS(resolved_segments_list) // 再次解决重叠

    RETURN resolved_segments_list
```

---

### 3. 时空复杂度分析

设查询序列Query长度为 N，参考序列Reference长度为 M。设 k 为k-mer的长度。

设算法在过滤后，用于构建图的锚点数量为 A。

#### 3.1 时间复杂度

1. **k-mer索引构建与查找 (`FindExactKmerMatches`)**:
    
    - 为Reference构建k-mer哈希表：平均 O(M)。
    - 遍历Query查找匹配：平均 O(N)。
    - 总计：**O(N + M)**。
2. **锚点延伸 (`ExtendKmerMatch`)**:
    
    - 对于每个种子，延伸的长度最坏情况下可能与锚点本身长度 `L_anchor` 成正比。
    - Indel检查通常涉及固定小范围（如1-2bp）。
    - 单次延伸近似 **O(L_anchor)**。
3. **发现所有初始锚点 (`FindAnchors` 主循环部分)**:
    
    - 设共发现 `E_kmers` 个精确k-mer匹配（种子）。`E_kmers` 的数量可能与 `N` 或 `M` 相关，最坏情况下可能很大，但实际中通常受序列特性限制。
    - 延伸这些种子：`E_kmers * O(L_avg_anchor)`，其中 `L_avg_anchor` 是平均锚点延伸长度。
    - 锚点过滤 (`FilterOverlappingAnchors`): 如果基于得分排序后，通过两两比较来移除重叠锚点，复杂度为 **O(A log A + A^2)** （排序 + 比较）。如果使用更高级的区间树或扫描线算法，可以优化到 O(A log A)。当前提供的Python/Go代码实现更接近 O(A^2)。
    - 此步骤会针对几种不同的 `k` 值运行，但 `k` 的取值数量是一个小常数。
4. **图构建 (`BuildSegmentGraph`)**:
    
    - 需要比较 `A` 个锚点中的任意两个，以确定是否存在边。最坏情况下边的数量可能是 O(A^2)。
    - 复杂度为 **O(A^2)**。
5. **寻找最大权重路径 (`FindMaximumWeightPath`)**:
    
    - 在有向无环图(DAG)上，此算法的复杂度为 O(V+E)，其中V是节点数（`A+2`），E是边数。
    - 由于E可以是 O(A^2)，此步骤复杂度为 **O(A^2)**。
6. **片段合并 (`MergeAdjacentSegments`, `ResolveOverlaps`)**:
    
    - 如果片段已排序，则为线性扫描 **O(A_segments)**，其中 `A_segments` 是当前阶段的片段数。排序需要 O(A_segments log A_segments)。
7. **确保完全覆盖 (`EnsureCompleteCoverage`)**:
    
    - 这一步的复杂度最难精确估计，因为它可能递归地调用锚点发现的逻辑（`FindMatchesInLargeRegion` / `FindMatchesInRegion`）来处理未覆盖区域。
    - 如果未覆盖区域很多或很大，并且都需要复杂的二次匹配，此步骤可能成为瓶颈。
    - 回退策略（Fallback）相对较快，大致与未覆盖区域总长度成正比。

总体时间复杂度:

考虑到最耗时的步骤通常是锚点过滤（O(A^2)）和图的构建与路径查找（O(A^2)），算法的整体时间复杂度主要受锚点数量 A 的影响。

A 的值取决于序列的相似性、重复区域的多少以及过滤参数的严格程度。在最坏情况下（例如，序列高度重复导致大量锚点），A 可能与 N 或 M 的较小者成比例。

因此，该算法的实际时间复杂度可以近似为 O(N + M + A^2)。

#### 3.2 空间复杂度

1. **存储输入序列**: O(N + M)。
2. **k-mer哈希表**: 平均情况下 O(M) 或 O(M*k)（取决于实现，如果k-mer字符串作为键，则与k相关）。
3. **锚点列表**: O(A) 个锚点，每个锚点存储固定数量的信息（坐标、得分等）。
4. **`processed_kmer_starts` 集合**: 最坏情况下可能达到 O(N) 或 O(M)。
5. **片段图表示**:
    - 邻接表表示法：O(V+E) = O(A + E_graph)。如果图是稠密的，`E_graph` 可能达到 O(A^2)。
6. **动态规划表 (用于最长路径)**: O(A) 用于存储距离和前驱节点。
7. **中间片段列表**: O(A_final) 用于存储最终和中间阶段的片段。

总体空间复杂度:

主要由k-mer索引、锚点列表和图的表示决定。

可以近似为 O(N + M + A + E_graph)。如果图非常稠密，可能达到 O(N + M + A^2)。
### 实验结果
result1:
```
[(0, 6820, 0, 6820), (6820, 6848, 6810, 6837), (6848, 6873, 6848, 6873), (6873, 6903, 16216, 16249), (6903, 6987, 22842, 22926), (6987, 7107, 6987, 7102), (7107, 7202, 22627, 22722), (7202, 7286, 7205, 7286), (7286, 19681, 10146, 22543), (19681, 19767, 10061, 10147), (19767, 19795, 16086, 16117), (19795, 19963, 9865, 10033), (19963, 19993, 9827, 9858), (19993, 20005, 19993, 20005), (20005, 20033, 8808, 8842), (20033, 20068, 9760, 9795), (20068, 20097, 11113, 11144), (20097, 20141, 9687, 9731), (20141, 20173, 11556, 11587), (20173, 20478, 9350, 9655), (20478, 20509, 12961, 12994), (20509, 20663, 9165, 9319), (20663, 20691, 12348, 12376), (20691, 20924, 8904, 9137), (20924, 20954, 12240, 12270), (20954, 20961, 20954, 20961), (20961, 20990, 11721, 11751), (20990, 21023, 8805, 8838), (21023, 21051, 18296, 18323), (21051, 21054, 21051, 21054), (21054, 21086, 14782, 14812), (21086, 21240, 8588, 8742), (21240, 21270, 10875, 10906), (21270, 21287, 21270, 21287), (21287, 21316, 21545, 21577), (21316, 21376, 8452, 8512), (21376, 21409, 20118, 20150), (21409, 21457, 8371, 8419), (21457, 21488, 15828, 15859), (21488, 21624, 8204, 8340), (21624, 22215, 21619, 22209), (22215, 22268, 7560, 7613), (22268, 22556, 22267, 22554), (22556, 22586, 7242, 7272), (22586, 22716, 22590, 22713), (22716, 22818, 7010, 7112), (22818, 22851, 19384, 19415), (22851, 27604, 22852, 27604), (27604, 27653, 2183, 2229), (27653, 27693, 27654, 27694), (27693, 27742, 2090, 2140), (27742, 28053, 27743, 28054), (28053, 28088, 28731, 28764), (28088, 28403, 28089, 28404), (28403, 28431, 28420, 28449), (28431, 28633, 28432, 28634), (28633, 28661, 1620, 1649), (28661, 29428, 28662, 29429), (29428, 29460, 315, 343), (29460, 29845, 29461, 29830)]
```
result2:
```
[(0, 295, 0, 295), (295, 595, 395, 695), (595, 596, 595, 596), (596, 699, 699, 799), (699, 723, 1232, 1269), (723, 724, 723, 724), (724, 771, 674, 718), (771, 801, 621, 652), (801, 833, 39, 74), (833, 904, 732, 802), (904, 929, 904, 929), (929, 999, 701, 769), (999, 1320, 697, 1011), (1320, 1322, 1320, 1322), (1322, 1398, 923, 998), (1398, 1404, 1398, 1404), (1404, 1442, 394, 435), (1442, 1462, 1621, 1654), (1462, 1487, 1462, 1487), (1487, 1572, 989, 1068), (1572, 1588, 1572, 1588), (1588, 1701, 1290, 1403), (1701, 1706, 1, 6), (1706, 1829, 1204, 1325), (1829, 1884, 1129, 1185), (1884, 1999, 1381, 1499), (1999, 2049, 299, 349), (2049, 2084, 245, 285), (2084, 2296, 384, 596), (2296, 2500, 1495, 1700)]
```