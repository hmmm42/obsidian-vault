```go
type TrieNode[T any] struct {
	val      T
	children map[rune]*TrieNode[T]
	isEnd    bool
}
type TrieMap[T any] struct {
	size int
	root *TrieNode[T]
}

func NewTrieMap[T any]() *TrieMap[T] {
	var zeroVal T
	return &TrieMap[T]{0, &TrieNode[T]{
		val:      zeroVal,
		children: make(map[rune]*TrieNode[T]),
		isEnd:    false,
	}}
}

func (t *TrieMap[T]) Size() int {
	return t.size
}

func getTrieNode[T any](node *TrieNode[T], key string) *TrieNode[T] {
	p := node
	for _, c := range key {
		if p == nil {
			return nil
		}
		p = p.children[c]
	}
	return p
}

func (t *TrieMap[T]) Get(key string) (T, bool) {
	x := getTrieNode(t.root, key)
	if x == nil || !x.isEnd {
		var zeroVal T
		return zeroVal, false
	}
	return x.val, true
}

func (t *TrieMap[T]) ContainsKey(key string) bool {
	_, ok := t.Get(key)
	return ok
}

func (t *TrieMap[T]) ShortestPrefixOf(query string) string {
	p := t.root
	for i, c := range query {
		if p == nil {
			return ""
		}
		if p.isEnd {
			return query[:i]
		}
		p = p.children[c]
	}
	if p != nil && p.isEnd {
		return query
	}
	return ""
}

func (t *TrieMap[T]) LongestPrefixOf(query string) string {
	p := t.root
	maxLen := 0
	for i, c := range query {
		if p == nil {
			break
		}
		if p.isEnd {
			maxLen = i
		}
		p = p.children[c]
	}
	if p != nil && p.isEnd {
		return query
	}
	return query[:maxLen+1]
}

func (t *TrieMap[T]) KeysWithPrefix(prefix string) []string {
	var res []string
	x := getTrieNode(t.root, prefix)
	if x == nil {
		return res
	}

path := []rune(prefix)

	var trav func(node *TrieNode[T])
	trav = func(node *TrieNode[T]) {
		if node == nil {
			return
		}
		if node.isEnd {
			res = append(res, string(path))
		}
		for c, child := range node.children {
			path = append(path, c)
			trav(child)
			path = path[:len(path)-1]
		}
	}
	trav(x)
	return res
}

func (t *TrieMap[T]) KeysWithPattern(pattern string) []string {
	var res []string
	var path []rune
	var trav func(node *TrieNode[T], i int)
	trav = func(node *TrieNode[T], i int) {
		if node == nil {
			return
		}
		if i == len(pattern) {
			if node.isEnd {
				res = append(res, string(path))
			}
		}
		c := []rune(pattern)[i]
		if c == '.' {
			for nxt, child := range node.children {
				path = append(path, nxt)
				trav(child, i+1)
				path = path[:len(path)-1]
			}
		} else {
			path = append(path, c)
			trav(node.children[c], i+1)
			path = path[:len(path)-1]
		}
	}
	trav(t.root, 0)
	return res
}

func (t *TrieMap[T]) HasKeysWithPattern(pattern string) bool {
	var check func(node *TrieNode[T], i int) bool
	check = func(node *TrieNode[T], i int) bool {
		if node == nil {
			return false
		}
		if i == len(pattern) {
			return node.isEnd
		}
		c := []rune(pattern)[i]
		if c != '.' {
			return check(node.children[c], i+1)
		}
		for _, child := range node.children {
			if check(child, i+1) {
				return true
			}
		}
		return false
	}
	return check(t.root, 0)
}

func (t *TrieMap[T]) Put(key string, val T) {
	if !t.ContainsKey(key) {
		t.size++
	}
	var put func(node *TrieNode[T], i int) *TrieNode[T]
	put = func(node *TrieNode[T], i int) *TrieNode[T] {
		if node == nil {
			node = &TrieNode[T]{children: make(map[rune]*TrieNode[T])}
		}
		if i == len(key) {
			node.val = val
			node.isEnd = true
			return node
		}
		c := []rune(key)[i]
		node.children[c] = put(node.children[c], i+1)
		return node
	}
	t.root = put(t.root, 0)
}

func (t *TrieMap[T]) Remove(key string) {
	if !t.ContainsKey(key) {
		return
	}
	t.size--
	var remove func(node *TrieNode[T], i int) *TrieNode[T]
	remove = func(node *TrieNode[T], i int) *TrieNode[T] {
		if node == nil {
			return nil
		}
		if i == len(key) {
			node.isEnd = false
		} else {
			c := []rune(key)[i]
			node.children[c] = remove(node.children[c], i+1)
		}
		if node.isEnd {
			return node
		}
		for _, child := range node.children {
			if child != nil {
				return node
			}
		}
		return nil
	}
	t.root = remove(t.root, 0)
}

```