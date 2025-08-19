实现一个支持并发的 Map，它具备$O(1)$的插入、查询操作，并且在查询的键不存在时能够阻塞等待，直到键被插入或等待超时。

==解决惊群效应:==
它虽然**触发了"群起"**, 但由于被唤醒的协程都有明确且必定成功的目标 (获取已存在的数据), 从而**避免了"效应"** (即大量无效唤醒和再次休眠造成的资源浪费).
```go
type ConcurrentMap[K comparable, V any] struct {
	sync.Mutex
	mp      map[K]V
	keyToCh map[K]chan struct{}
}

func NewConcurrentMap[K comparable, V any]() *ConcurrentMap[K, V] {
	return &ConcurrentMap[K, V]{
		mp:      make(map[K]V),
		keyToCh: make(map[K]chan struct{}),
	}
	// Mutex 是结构体, 不需要初始化
}

func (m *ConcurrentMap[K, V]) Put(k K, v V) {
	m.Lock()
	defer m.Unlock()
	m.mp[k] = v
	
	ch, ok := m.keyToCh[k] //检查有没有并发等待读的协程
	if !ok {
		return
	}
	//思路一: 直接删除key
	//close(ch) // 唤醒所有阻塞中的读协程
	//delete(m.keyToCh, k) // 保证不会关闭channel两次
	
	//思路二: 多路复用
	//每次select只会执行一个分支的内容
	select {
	case <-ch: //如果读到了, 说明已经关闭了
		return
	default:
		close(ch)
	}
	
	//思路三: 包装ch, 加上sync.Once
}

func (m *ConcurrentMap[K, V]) Get(k K, maxWaitingDuration time.Duration) (V, error) {
	m.Lock()
	v, ok := m.mp[k]
	if ok {
		m.Unlock()
		return v, nil
	}

	// 无数据, 需要阻塞直到有写协程
	ch, ok := m.keyToCh[k]
	if !ok {
		ch = make(chan struct{})
		m.keyToCh[k] = ch
	}
	
	m.Unlock() //先解锁再进入新的阻塞, 防止死锁
	select {
	case <-time.After(maxWaitingDuration):
		var zero V
		return zero, errors.New("timeout")
	case <-ch:
	}
	
	m.Lock()
	v = m.mp[k]
	m.Unlock()
	return v, nil
}

```