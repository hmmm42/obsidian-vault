#字符串 #KMP
KMP 算法不仅可以寻找子串
# 构造最长真前后缀数组
```go
m := len(pat)
lps := make([]int, m)
j := 0
for i := 1; i < m; i++ {
	for j > 0 && pat[i] != pat[j] {
		j = lps[j-1]
	}
	// 循环结束后, j == 0 或者找到匹配
	if pat[i] == pat[j] {
		j++ // j 是下标, 转成长度要加1
	}
	lps[i] = j
}
```

# 运用
```go
n := len(txt)
j := 0
for i := range n {
	for j > 0 && txt[i] != pat[j] {
		// 如果 pat[j] 和 txt[i] 不匹配，并且 j > 0 
		// 说明模式串已经匹配了一部分 (长度为 j) 
		// 此时，根据 LPS 数组，将模式串的索引 j 回溯到 lps[j-1] 的位置 
		// 文本串的索引 i 不变，因为我们只是移动模式串来寻找下一个可能的匹配点
		j = lps[j-1]
	}
	// 循环结束后, j == 0 或者找到匹配
	if txt[i] == pat[j] {
		j++
	}
	if j == m {
		res.append(res, i-m+1)
	}
}
```
