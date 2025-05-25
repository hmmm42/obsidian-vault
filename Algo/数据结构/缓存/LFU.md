维护3个哈希表:
- key 到 val 的映射     `map[int]int KV`
- key 到 freq 的映射    `map[int]int KF`
- freq 到 key 列表的映射 `map[int]LinkedHashSet FK`
遇到访问次数相同的情况, 使用[[LRU]]进行删除, LRU 用map+双向链表实现`LinkedHashSet`