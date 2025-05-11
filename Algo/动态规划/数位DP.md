#DP #数位DP
处理与数位有关的问题, 主要是计数问题

模版:
```go
var dp func(i int, limit, isNum bool) int
```
- `dp(iint, limit, isNum bool)`: 计算从第`i`位开始满足的合法方案数
- `limit`: 是否限制当前位的数字, 代表目前已填(或不填)的数字都匹配
	- `true`: 第`i`位填的数字最多为`target[i]`
	- `false`: 最多为9 
- `isNum`: 是否已经填过数字
	- `true`: 则必须填数字，且要填入的数字从 0 开始
	- `false`: 当前位可以跳过（不填数字, 也可理解为前导0），或者要填入的数字至少为 1

问：什么情况下必须要有 `isNum` 参数？

答：考虑这样一个问题，计算 `[0,n]` 中，有多少个数 x 满足：
统计 x 的每个数位，要求 0,1,2,⋯,9 的出现次数都是偶数。这里如果把前导零也统计进去的话，就会和 x 中的 0 混在一起了，没法判断 x 中的 0 是否出现了偶数次。

**总结: 加入`isNum`是为了方便判断前导0**

记忆化搜索 `memo`: 一般存储 `!isLimit && isNum` 时的状态

eg. 给定一个整数 `n`，计算所有小于等于 `n` 的非负整数中数字 `1` 出现的个数
dp定义: 前 i 位有 cnt​ 个 1 的前提下，能构造出的数中的 1 的个数总和
```go
func countDigitOne(n int) int {
	s := strconv.Itoa(n)
	m := len(s)

	// 记忆化2个维度: 
	memo := make([][]int, m)
	for i := range m {
		memo[i] = make([]int, m)
		for j := range m {
			memo[i][j] = -1
		}
	}
	
	var dp func(i, cnt int, limit, isNum bool) int
	dp = func(i, cnt int, limit, isNum bool) (res int) {
		if i == m {
			return cnt
		}
		
		// 仅当不受限制 (limit=false) 且已经开始构建数字 (isNum=true)时进行记忆化 
		// 因为只有这种状态下的子问题结果是固定且会被重复调用的
		if !limit && isNum {
			if memo[i][cnt] >= 0 {
				return memo[i][cnt]
			}
			defer func() { memo[i][cnt] = res }()
		}
		
		// 选择不填的情况
		if !isNum {
			res += dp(i+1, cnt, false, false)
		}

		// 以下都是选择填
		low := 0
		if !isNum {
			low = 1
		}
		
		up := 9
		if limit {
			up = int(s[i]-'0')
		}
		for d := low; d <= up; d++ {
			newCnt := cnt
			if d == 1 {
				newCnt++
			}
			res += dp(i+1, newCnt, limit && d == up, true)
		}
		
		// 返回时没有包含全都不填的情况(为0), 根据情况自主加上
		return dp(0, 0, true, false) 
	}

```

eg. 结合[[位运算]]:
给定一个正整数 `n` ，请你统计在 `[0, n]` 范围的非负整数中，有多少个整数的二进制表示中不存在 **连续的 1** 。

```go
func findIntegers(n int) int {
	m := bits.Len(uint(n))
	memo := make([][2]int, m)
	for i := range memo {
		memo[i] = [2]int{-1, -1}
	}
	// 新的 pre1 维度要保存进记忆化中
	var dp func(i, pre1 int, limit, isNum bool) int
	dp = func(i, pre1 int, limit, isNum bool) (res int) {
		if i < 0 {
			if isNum {
				return 1
			} else {
				return 0
			}
		}
		if !limit && isNum {
			if memo[i][pre1] >= 0 {
				return memo[i][pre1]
			}
			defer func() { memo[i][pre1] = res }()
		}
		if !isNum {
			res += dp(i-1, 0, false, false)
		}
		low := 0
		if !isNum {
			low = 1
		}
		up := 1
		if limit {
			up = n >> i & 1 //因为这题采用了位运算, 所以从高位到低位
		}
		// pre1=true时只能填0, 否则可以填0/1
		for d := low; d <= up; d++ {
			if pre1 == 1 && d == 1 {
				continue
			}
			res += dp(i-1, d, limit && d == up, true)
		}
		return res
	}
	// 处理时忽略了全都不填的情况(0), 最后要加上
	return dp(m-1, 0, true, false) + 1
}

```

## 有上下界
给你两个正整数 `l` 和 `r` 。如果正整数每一位上的数字的乘积可以被这些数字之和整除，则认为该整数是一个 **美丽整数** 。

统计并返回 `l` 和 `r` 之间（包括 `l` 和 `r` ）的 **美丽整数** 的数目。
### isNum ver.
```go
func beautifulNumbers(l int, r int) int {
  type tuple struct{i, m, s int}
  memo := make(map[tuple]int)
  var str []byte

  var dp func(i, m, s int, limit, isNum bool) int
  dp = func(i, m, s int, limit, isNum bool) (res int) {
    if i < 0 {
      if s == 0 || m%s != 0 { // 自动排除了 0 的情况（全都不选）
        return 0
      }
      return 1
   }
    if !limit && isNum {
     t := tuple{i, m, s}
     if v, ok := memo[t]; ok {
        return v
      }
      defer func() {memo[t] = res}()
    }
    if !isNum {
      res += dp(i-1, 1, 0, false, false)
    }

    lo := 0
    if !isNum {
      lo = 1
    }
    up := 9
    if limit {
      up = int(str[i]-'0')
    }

    for d := lo; d <= up; d++ {
      res += dp(i-1, m*d, s+d, limit&&d==up, true)
    }
    return
  }

  calc := func(n int) int {
    str = []byte(strconv.Itoa(n))
    slices.Reverse(str)
    return dp(len(str)-1, 1, 0, true, false)
  }
  return calc(r) - calc(l-1)
}
```
由于上下界的长度可能不同, 为了复用**记忆化搜索**, 需要将字符串反转, 并且右对齐, 否则会出错:
如 `r = 12345`, `l = 123` => `l = 12300`

### limitL, limitR ver.
*代码实现时，如果 `limitL=true`，且 i 比 r 和 l 的十进制长度之差还小，那么当前数位可以不填。这样就无需 isNum 参数了*

```go
func beautifulNumbers(l int, r int) int {
	low, high := strconv.Itoa(l), strconv.Itoa(r)
	n := len(high)
	diffLH := n - len(low)
	type tuple struct{ i, m, s int }
	memo := make(map[tuple]int)
	var dp func(i, m, s int, limitL, limitR bool) int
	dp = func(i, m, s int, limitL, limitR bool) (res int) {
		if i == n {
			if s == 0 || m%s > 0 {
				return 0
			} else {
				return 1
			}
		}
		if !limitL && !limitR {
			cur := tuple{i, m, s}
			if v, ok := memo[cur]; ok {
				return v
			}
			defer func() { memo[cur] = res }()
		}
		lo := 0
		if limitL && i >= diffLH {
			lo = int(low[i-diffLH]-'0')
		}
		up := 9
		if limitR {
			up = int(high[i]-'0')
		}
		d := lo
		if limitL && i < diffLH { // 相当于 isNum
			res += dp(i+1, 1, 0, true, false) // 不填, 前面没有数相当于乘积=1
			d = 1
			// 不能 lo = 1; for d := lo; d <= up; d++
			// 下面递归dp, newLimitL 需要 limitL&&d==lo
		}
		for ; d <= up; d++ {
			res += dp(i+1, m*d, s+d, limitL&&d==lo, limitR&&d==up)
		}
		return
	}
	return dp(0, 1, 0, true, true)
}
```


## 结合[[KMP]]
给你两个长度为 `n` 的字符串 `s1` 和 `s2` ，以及一个字符串 `evil` 。请你返回 **好字符串** 的数目。

**好字符串** 的定义为：它的长度为 `n` ，字典序大于等于 `s1` ，字典序小于等于 `s2` ，且不包含 `evil` 为子字符串。

```go
func findGoodStrings(n int, s1 string, s2 string, evil string) int {
	m := len(evil)
	memo := make([][]int, n)
	for i := range memo {
		memo[i] = make([]int, m)
		for j := range memo[i] {
			memo[i][j] = -1
		}
	}
	// kmp
	lps := make([]int, m)
	j := 0
	for i := 1; i < m; i++ {
		for j > 0 && evil[i] != evil[j] {
			j = lps[j-1]
		}
		// 循环结束后, j == 0 或者找到匹配
		if evil[i] == evil[j] {
			j++
		}
		lps[i] = j
	}
	
	MOD := int(1e9 + 7)
	var dp func(i, match int, limitL, limitR bool) int
	dp = func(i, match int, limitL, limitR bool) (res int) {
		if match >= m { 
		// 不等构造完字符串就剪枝, 因为后面含有 evil 的都是无效的
			return 0
		}
		if i == n {
			return 1
		}
		if !limitL && !limitR {
			if memo[i][match] != -1 {
				return memo[i][match]
			}
			defer func() { memo[i][match] = res }()
		}
		lo := byte('a')
		if limitL {
			lo = s1[i]
		}
		up := byte('z')
		if limitR {
			up = s2[i]
		}
		for c := lo; c <= up; c++ {
			newMatch := match
			// 执行 KMP
			// 这里不是匹配完整的模式串, 而是匹配前缀
			for newMatch > 0 && evil[newMatch] != c {
				newMatch = lps[newMatch-1]
			}
			if evil[newMatch] == c {
				newMatch++
			}
			
			res += dp(i+1, newMatch, limitL && c == lo, limitR && c == up) % MOD
		}
		return res % MOD
	}
	return dp(0, 0, true, true)
}

```
此处 KMP 对新添加字符的处理逻辑: 失配时回退到**最近有效前缀位置**