# [[优先队列]]
优先队列中保存链表节点, 动态添加下一个

# 分治
思路类似[[归并排序]]
反复调用**合并2条有序链表**的函数, 同时保持递归树平衡, 实现$O(n \log k)$复杂度 
```go
func mergeKLists(lists []*ListNode) *ListNode {
	if len(lists) == 0 {
		return nil
	}
	var merge func(int, int) *ListNode
	merge = func(start, end int) *ListNode {
		if start == end {
			return lists[start]
		}
		
		mid := start + (end-start)/2
		left := merge(start, mid)
		right := merge(mid+1, end)
		
		//merge two lists
		dummy := &ListNode{-1, nil}
		p, p1, p2 := dummy, left, right
		for p1 != nil && p2 != nil {
			if p1.Val < p2.Val {
				p.Next = p1
				p1 = p1.Next
			} else {
				p.Next = p2
				p2 = p2.Next
			}
			p = p.Next
		}
		// 注意剩下的部分直接接上去就行了, 不用再遍历
		if p1 != nil { 
			p.Next = p1
		}
		if p2 != nil {
			p.Next = p2
		}
		return dummy.Next
	}
	
	return merge(0, len(lists)-1)
}

```