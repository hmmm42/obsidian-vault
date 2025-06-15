是[[BFS模板|BFS]]的扩展
使用的前提: 路径中每增加一条边，路径的总权重就会增加/减少
面试时[[优先队列]]用标准库实现
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