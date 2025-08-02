维护3个哈希表:
- key 到 val 的映射     `map[int]int KV`
- key 到 freq 的映射    `map[int]int KF`
- freq 到 key 列表的映射 `map[int]LinkedHashSet FK`
遇到访问次数相同的情况, 使用[[LRU]]进行删除, LRU 用map+双向链表实现`LinkedHashSet`

```go
type LinkedHashSet struct {
	elements map[int]*list.Element
	order    *list.List
}

func NewLinkedHashSet() *LinkedHashSet {
	return &LinkedHashSet{
		elements: make(map[int]*list.Element),
		order:    list.New(),
	}
}

func (s *LinkedHashSet) Add(value int) {
	if _, exists := s.elements[value]; !exists {
		elem := s.order.PushBack(value)
		s.elements[value] = elem
	}
}

func (s *LinkedHashSet) Remove(value int) {
	if elem, exists := s.elements[value]; exists {
		s.order.Remove(elem)
		delete(s.elements, value)
	}
}

func (s *LinkedHashSet) GetHead() int {
	if s.Size() == 0 {
		return -1
	}
	head := s.order.Front()
	return head.Value.(int)
}

func (s *LinkedHashSet) Size() int {
	return s.order.Len()
}

type LFUCache struct {
	KV           map[int]int
	KF           map[int]int
	FK           map[int]LinkedHashSet
	minFreq, cap int
}

func _(capacity int) LFUCache {
	return LFUCache{
		KV:      make(map[int]int),
		KF:      make(map[int]int),
		FK:      make(map[int]LinkedHashSet),
		minFreq: 0,
		cap:     capacity,
	}
}

func (this *LFUCache) increaseFreq(key int) {
	freq := this.KF[key]
	this.KF[key] = freq + 1
	keyList := this.FK[freq]
	keyList.Remove(key)
	if keyList.Size() == 0 {
		delete(this.FK, freq)
		if freq == this.minFreq {
			this.minFreq++
		}
	}
	if _, found := this.FK[freq+1]; !found {
		this.FK[freq+1] = *NewLinkedHashSet()
	}
	newF := this.FK[freq+1]
	newF.Add(key)
}

func (this *LFUCache) removeMinFreqKey() {
	keyList := this.FK[this.minFreq]
	d := keyList.GetHead()
	keyList.Remove(d)
	if keyList.Size() == 0 {
		delete(this.FK, this.minFreq)
	}
	delete(this.KV, d)
	delete(this.KF, d)
}

func (this *LFUCache) Get(key int) int {
	if _, found := this.KV[key]; !found {
		return -1
	}
	this.increaseFreq(key)
	return this.KV[key]
}

func (this *LFUCache) Put(key int, value int) {
	if _, found := this.KV[key]; found {
		this.KV[key] = value
		this.increaseFreq(key)
		return
	}
	if this.cap == len(this.KV) {
		this.removeMinFreqKey()
	}
	this.KV[key] = value
	this.KF[key] = 1
	if _, found := this.FK[1]; !found {
		this.FK[1] = *NewLinkedHashSet()
	}
	keyList := this.FK[1]
	keyList.Add(key)
	this.minFreq = 1
}

```