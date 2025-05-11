**注意要跳过相同元素, 在`n>2`部分和`n=2`部分分别执行**
```go
// 注意：调用这个函数之前一定要先给 nums 排序
// n 填写想求的是几数之和，start 从哪个索引开始计算（一般填 0），target 填想凑出的目标和
func nSumTarget(nums []int, n int, start int, target int64) [][]int {
	sz := len(nums)
	res := [][]int{}
	// 至少是 2Sum，且数组大小不应该小于 n
	if n < 2 || sz < n {
		return res
	}
	// 2Sum 是 base case
	if n == 2 {
		// 双指针那一套操作
		lo, hi := start, sz-1
		for lo < hi {
			sum := nums[lo] + nums[hi]
			left, right := nums[lo], nums[hi]
			if int64(sum) < target {
				for lo < hi && nums[lo] == left {
					lo++
				}
			} else if int64(sum) > target {
				for lo < hi && nums[hi] == right {
					hi--
				}
			} else {
				res = append(res, []int{left, right})
				for lo < hi && nums[lo] == left {
					lo++
				}
				for lo < hi && nums[hi] == right {
					hi--
				}
			}
		}
	} else {
		// n > 2 时，递归计算 (n-1)Sum 的结果
		for i := start; i < sz; i++ {
			subs := nSumTarget(nums, n-1, i+1, target-int64(nums[i]))
			for _, sub := range subs {
				// (n-1)Sum 加上 nums[i] 就是 nSum
				sub = append(sub, nums[i])
				res = append(res, sub)
			}
			for i < sz-1 && nums[i] == nums[i+1] {
				i++
			}
		}
	}
	return res
}
```
