```go
// 返回链表的倒数第 k 个节点
func findFromEnd(head *ListNode, k int) *ListNode {
    p1 := head
    // p1 先走 k 步
    for i := 0; i < k; i++ {
        p1 = p1.Next
    }
    p2 := head
    // p1 和 p2 同时走 n - k 步
    for p1 != nil {
        p1 = p1.Next
        p2 = p2.Next
    }
    // p2 现在指向第 n - k + 1 个节点，即倒数第 k 个节点
    return p2
}
```
删除时使用虚拟头节点技巧