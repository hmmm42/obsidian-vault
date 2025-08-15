算法的核心思想是“**做尽可能小的妥协，并让妥协发生在尽可能低位**”。 ==从右向左==
1. **目标**：构造一个小于 `n` 的最大数。为了让这个数最大，我们希望它的==高位（左侧）数字尽可能地与 `n` 保持一致==。
2. **寻找修改点**：我们从 `n` 的最右边（个位）开始，向左寻找一个可以“降级”的数位。所谓“降级”，就是用一个 `A` 中比 `n` 在该位的数字更小的数来替换它。
3. **最优修改点**：我们找到的第一个（从右往左）可以成功“降级”的位置，就是最优的修改点。因为任何比它更靠左的修改，都会对数字的整体大小造成更大的“伤害”，导致结果变小。
4. **构造结果**：一旦在第 `i` 位成功“降级”，这个数的前缀 `0` 到 `i-1` 位就保持和 `n` 一致，第 `i` 位使用那个更小的数字，而 `i` 后面的所有低位都填上 `A` 中允许的最大数字 `maxDigit`，以确保最终结果是所有可能性中的最大值。
5. **备用方案**：如果从右到左都找不到任何可以“降级”的位置，说明无法构造出和 `n` 同等位数的、且小于 `n` 的数。那么答案必然是比 `n` 少一位的数，这个数由 `len(n)-1` 个 `maxDigit` 组成。
==为什么不用数位DP: 数位DP用于计数, 找所有情况, 复杂度偏高==
```go
func solution(A []int, num int) int {
	sort.Ints(A)
	str := strconv.Itoa(num)
	digits := []byte(str)
	check := make(map[int]bool)
	for i, d := range digits { // 确认某个前缀是否能被A中的数所组成
		for _, x := range A {
			if x == int(d-'0') {
				check[i] = true
				break
			}
		}
		if !check[i] {
			break
		}
	}
	check[-1] = true
	for i := len(digits) - 1; i >= 0; i-- {
		cur := int(digits[i]-'0')
		if !check[i-1] {
			continue
		}
		newD := 0
		for j := len(A)-1; j >= 0; j-- {
			if A[j] < cur {
				newD = A[j]
				break
			}
		}
		if newD != 0 {
			resStr := str[:i]
			resStr += strconv.Itoa(newD)
			resStr += strings.Repeat(strconv.Itoa(A[len(A)-1]), len(str)-i-1)
			res, _ := strconv.Atoi(resStr)
			return res
		}
	}
	if len(str) > 1 {
		res := 0
		for range len(str)-1 {
			res = res*10 + A[len(A)-1]
		}
		return res
	}
	return -1
}

```