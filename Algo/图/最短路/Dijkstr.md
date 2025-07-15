==单源最短路径, 不能处理负权重边==
是[[BFS模板|BFS]]的扩展
- ! 如果权重都是1, 直接用标准 BFS 

使用的前提: 路径中每增加一条边，路径的总权重就会增加/减少
面试时[[优先队列]]用标准库实现
复杂度$O(|V|+|E|)$
```go
func networkDelayTime(times [][]int, n int, k int) int {
	graph := make([][]struct{ to, wgt int }, n+1)
	for _, e := range times {
		graph[e[0]] = append(graph[e[0]], struct{ to, wgt int }{e[1], e[2]})
	}
	type state struct {
		id   int
		dist int
	}
	dist := make([]int, n+1)
	for i := range dist {
		dist[i] = math.MaxInt
	}

	pq := priorityqueue.NewWith[state](func(x, y state) int {
		return x.dist - y.dist
	})
	pq.Enqueue(state{k, 0})
	dist[k] = 0
	for pq.Size() > 0 {
		cur, _ := pq.Dequeue()
		if cur.dist > dist[cur.id] {
			continue
		}
		for _, neighbor := range graph[cur.id] {
			v, w := neighbor.to, neighbor.wgt
			if dist[v] > dist[cur.id]+w {
				dist[v] = dist[cur.id] + w
				pq.Enqueue(state{v, dist[v]})
			}
		}
	}
	
	res := 0
	for i := 1; i <= n; i++ {
		if dist[i] == math.MaxInt {
			return -1
		}
		res = max(res, dist[i])
	}
	return res
}

```

ACM ver.
[【模板】单源最短路2_牛客题霸_牛客网](https://www.nowcoder.com/practice/7c1740c3d4ba4b3486df4847ee6e8fc7?tpId=308&tqId=2031489&sourceUrl=%2Fexam%2Foj%3Fpage%3D1%26tab%3D%25E7%25AE%2597%25E6%25B3%2595%25E7%25AF%2587%26topicId%3D295)
```go
func main() {
  n, m := 0, 0
  fmt.Scan(&n, &m)
  graph := make([][][2]int, 5001)
  for i := 0; i < m; i++ {
    var u, v, w int
    fmt.Scan(&u, &v, &w)
    graph[u] = append(graph[u], [2]int{v, w})
    graph[v] = append(graph[v], [2]int{u, w})
  }
  dis := make([]int, 5001)
  for i := range dis {
    dis[i] = math.MaxInt
  }
  dis[1] = 0

  var pq PQ
  heap.Push(&pq, [2]int{1, 0})
  for len(pq) > 0 {
    cur := heap.Pop(&pq).([2]int)
    u := cur[0]
    if cur[1] > dis[u] {
      continue
    }
    for _, nxt := range graph[u] {
      v, w := nxt[0], nxt[1]
      if dis[v] > dis[u] + w {
        dis[v] = dis[u] + w
        heap.Push(&pq, [2]int{v, dis[v]})
      }
    }
  }
  if dis[n] == math.MaxInt {
    fmt.Print(-1)
  } else {
    fmt.Print(dis[n])
  }
}

type PQ [][2]int // {id, dis}

func (pq PQ) Len() int           { return len(pq) }
func (pq PQ) Less(i, j int) bool { return pq[i][1] < pq[j][1] } // 小根堆
func (pq PQ) Swap(i, j int)      { pq[i], pq[j] = pq[j], pq[i] }
func (pq *PQ) Push(x any)        { *pq = append(*pq, x.([2]int)) }
func (pq *PQ) Pop() any {
	x := (*pq)[len(*pq)-1]
	*pq = (*pq)[:len(*pq)-1]
	return x
}

```