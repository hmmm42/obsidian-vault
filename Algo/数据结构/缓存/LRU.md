[[Algo/数据结构/哈希表#链表加强|链表加强哈希表]]
#hot100 
```go
type lruEntry struct {
	key   int
	value int
}
type LRUCache struct {
	ll    *list.List
	cache map[int]*list.Element
	sz    int
}

func Constructor(capacity int) LRUCache {
	return LRUCache{
		ll:    list.New(),
		cache: make(map[int]*list.Element),
		sz:    capacity,
	}
}

func (this *LRUCache) Get(key int) int {
	if ele, ok := this.cache[key]; ok {
		this.ll.MoveToFront(ele)
		return ele.Value.(*lruEntry).value
	} else {
		return -1
	}
}

func (this *LRUCache) Put(key int, value int) {
	if ele, ok := this.cache[key]; ok {
		//ele.Value.(lruEntry).value = value 不是指针类型无法分配
		ele.Value.(*lruEntry).value = value
		this.ll.MoveToFront(ele)
	} else {
		this.cache[key] = this.ll.PushFront(&lruEntry{key, value})
		if len(this.cache) > this.sz {
			delete(this.cache, this.ll.Back().Value.(*lruEntry).key)
			this.ll.Remove(this.ll.Back())
		}
	}
}

```