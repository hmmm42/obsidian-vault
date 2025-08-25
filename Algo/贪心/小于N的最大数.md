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

[902. 最大为 N 的数字组合 - 力扣（LeetCode）](https://leetcode.cn/problems/numbers-at-most-n-given-digit-set/description/)
#数位DP [[数位DP]]
```go
func atMostNGivenDigitSet(digits []string, n int) int {
    s := strconv.Itoa(n)
    m := len(s)
    
    // 记忆化数组，只与位数 i 相关
    // 因为 isNum=false 和 limit=true 的情况不记忆，所以只有 i 这一个维度
    memo := make([]int, m)
    for i := range memo {
        memo[i] = -1
    }

    var dp func(i int, limit, isNum bool) int
    dp = func(i int, limit, isNum bool) (res int) {
        // Base Case: 成功构造了一个数
        if i == m {
            if isNum { // 只要填过数字，就是一个有效的数
                return 1
            }
            return 0
        }
        
        // 记忆化：只在不受限且已填数字时
        if !limit && isNum {
            if memo[i] != -1 {
                return memo[i]
            }
            defer func() { memo[i] = res }()
        }

        // --- 递归主体 ---

        // 1. isNum=false 时，可以选择“跳过当前位”，去构造位数更少的数
        if !isNum {
            // 这个调用等价于计算所有位数 < m 的数字个数的总和
            res += dp(i+1, false, false)
        }

        // 2. 尝试在当前位 i 填入一个数字
        up := 9
        if limit {
            up = int(s[i] - '0')
        }

        // 遍历可用的数字
        for _, dStr := range digits {
            d, _ := strconv.Atoi(dStr)
            
            if d > up { // 如果当前数字已超过上限，后续的更大数字也不行
                break
            }
            
            // 累加方案数
            // isNum 变为 true，因为我们开始填数字了
            // 新的 limit 取决于之前的 limit 和当前是否选择了上限 d
            res += dp(i+1, limit && (d == up), true)
        }
        return
    }

    // 初始调用：从第0位开始，受n限制，还未填入数字
    // 注意：题目要求正整数，但我们的DP会把0也算进去（如果isNum=false一路走到底）
    // 但因为题目给的digits不包含'0'，所以isNum=false走到底会返回0，不会构成影响。
    // 如果digits包含'0'，最后可能需要减1。
    return dp(0, true, false)
}
```