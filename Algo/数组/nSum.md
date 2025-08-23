# 两数之和
#hot100
2种方法
双指针: 复杂度$O(n)$
```go
func twoSum(nums []int, target int) []int {
	// 维护 val -> index 的映射
	valToIndex := make(map[int]int)
	for i, num := range nums {
		// 查表，看看是否有能和 nums[i] 凑出 target 的元素
		need := target - num
		if j, ok := valToIndex[need]; ok {
			return []int{j, i}
		}
		// 存入 val -> index 的映射
		valToIndex[num] = i
	}
	return nil
}
```
如果需要去重, 需要用双指针
双指针: 需要先排序, 复杂度$O(n\log n)$
```go
func twoSum(nums []int, target int) [][]int {
    // 先对数组排序
    sort.Ints(nums)
    // 左右指针
    for lo < hi {
    sum := nums[lo] + nums[hi]
    // 记录索引 lo 和 hi 最初对应的值
    left, right := nums[lo], nums[hi]
    if sum < target {
        lo++
    } else if sum > target {
        hi--
    } else {
        res = append(res, []int{left, right})
        
        // 跳过所有重复的元素
        for lo < hi && nums[lo] == left {
            lo++
        }
        for lo < hi && nums[hi] == right {
            hi--
        }
		}
    return [][]int{}
}
```
# 三数之和
#hot100
**还不太熟练**
枚举每个元素(跳过相同的), 对其后面的元素执行两数之和
==记得去重只有在满足的时候, 而且一定要去重==
```go
func threeSum(nums []int) (res [][]int) {
	sort.Ints(nums)
	n := len(nums)
	for i, num := range nums {
		if i > 0 && num == nums[i-1] {
			continue
		}
		lo, hi, target := i+1, n-1, -num
		for lo < hi {
			l, r := nums[lo], nums[hi]
			sum := l + r
			if sum > target {
				hi--
			} else if sum < target {
				lo++
			} else {
				res = append(res, []int{num, l, r})
				for lo < hi && nums[lo] == l {
					lo++
				}
				for lo < hi && nums[hi] == r {
					hi--
				}
			}
		}
	}
	return
}
```
## 变式
[最接近的三数之和_牛客题霸_牛客网](https://www.nowcoder.com/practice/f889497fd1134af5af9de60b4d13af23?tpId=196&tqId=39665&rp=1&sourceUrl=%2Fexam%2Foj%3Fpage%3D1%26pageSize%3D50%26search%3D%25E4%25BA%258C%25E5%258F%2589%25E6%25A0%2591%25E5%25B1%2595%25E5%25BC%2580%26tab%3D%25E7%25AE%2597%25E6%25B3%2595%25E7%25AC%2594%25E9%259D%25A2%25E8%25AF%2595%25E7%25AF%2587%26topicId%3D196&difficulty=undefined&judgeStatus=undefined&tags=&title=%E6%9C%80%E6%8E%A5%E8%BF%91)
```go
func ClosestSum( nums []int ,  target int ) (res int) {
  res = nums[0] + nums[1] + nums[2]
  n := len(nums)
  sort.Ints(nums)
  for i, first := range nums {
    if i > 0 && first == nums[i-1] {
      continue
    }
    tar2Sum := target - first
    l, r := i+1, n-1
    for l < r {
      cur := nums[l] + nums[r]
      if math.Abs(float64(cur-tar2Sum)) < math.Abs(float64(res-target)) {
        res = first + cur
      }
      if cur < tar2Sum {
        l++
      } else if cur > tar2Sum {
        r--
      } else {
        return target
      }
    }
  }
  return res
}
```
# n数之和
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
[lc.560 和为k的子数组](https://leetcode.cn/problems/subarray-sum-equals-k/?envType=study-plan-v2&envId=top-100-liked)
#hot100 
通过前缀和, 转化为 2-sum 问题
```go
func subarraySum(nums []int, k int) (res int) {
  n := len(nums)
  preSum := make([]int, n+1)
  for i, num := range nums {
    preSum[i+1] = preSum[i] + num
  }
  mp := make(map[int]int)
  for _, v := range preSum {
    need := v - k
    res += mp[need]
    mp[v]++
  }
  return
}
```