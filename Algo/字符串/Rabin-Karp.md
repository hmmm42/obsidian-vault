---
~
---
#哈希表 #滑动窗口
[[滑动窗口]]

```go
// Rabin-Karp指纹字符串查找算法
func RabinKarp(txt string, pat string) int {
	// 位数
	L := len(pat)
	
	// 进制 (只考虑 ASCII 编码), 不用处理时转成 26 进制
 	R := 256
	
	// 取一个比较大的素数作为求模的除数
	Q := int64(1658598167)
	
	// R^(L - 1) 的结果
	var RL int64 = 1
	for range L-1 {
		// 计算过程中不断求模，避免溢出
		RL = (RL * R) % Q
	}
	
	// 计算模式串的哈希值，时间 O(L)
	var patHash int64 = 0
	for i := 0; i < len(pat); i++ {
		patHash = (int64(R) * patHash + int64(pat[i])) % Q
	}
	
	// 滑动窗口中子字符串的哈希值
	var windowHash int64 = 0
	
	// 滑动窗口代码框架，时间 O(N)
	left, right := 0, 0
	for right < len(txt) {
		// 扩大窗口，移入字符
		windowHash = (R * windowHash) % Q + txt[right]) % Q
		right++
		
		// 当子串的长度达到要求
		if right - left == L {
			// 根据哈希值判断是否匹配模式串
			if windowHash == patHash {
				// 当前窗口中的子串哈希值等于模式串的哈希值
				// 还需进一步确认窗口子串是否真的和模式串相同，避免哈希冲突
				if pat == txt[left:right] {
					return left
				}
			}
			// 缩小窗口，移出字符
			// 因为 windowHash - (txt[left] * RL) % Q 可能是负数
			// 所以额外再加一个 Q，保证 windowHash 不会是负数
			windowHash = ((windowHash - txt[left] * RL % Q) + Q) % Q
			left++
		}
	}
	// 没有找到模式串
	return -1
}

```
