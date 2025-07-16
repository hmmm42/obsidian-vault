用队列来记录每一层, 需要 FIFO
[【模板】单源最短路1_牛客题霸_牛客网](https://www.nowcoder.com/practice/f24504c9ff544f7c808f76693cc34af8?tpId=308&tqId=2031400&sourceUrl=%2Fexam%2Foj%3Fpage%3D1%26tab%3D%25E7%25AE%2597%25E6%25B3%2595%25E7%25AF%2587%26topicId%3D295)
```go
func main() {
  var n, m, u, v int
  fmt.Scan(&n, &m)
  graph := make([][]int, 5001)
  vis := make([]bool, 5001)
  for i := 0; i < m; i++ {
    fmt.Scan(&u, &v)
    graph[u] = append(graph[u], v)
    graph[v] = append(graph[v], u)
  }

  var q []int
  q = append(q, 1)
  dis := 0
  for len(q) > 0 {
    sz := len(q)
    for i := 0; i < sz; i++ {
      cur := q[0]
      if cur == n {
          fmt.Print(dis)
          return
        }
      q = q[1:]
      for _, nxt := range graph[cur] {
        if vis[nxt] {
          continue
        }
        
        vis[nxt] = true
        q = append(q, nxt)
      }
    }
    dis++
  }
  fmt.Print(-1)
}
```
**容易遗忘的地方:**
- `vis`的判断, 之后要置为`true`
- FIFO, 获取`q[0]`, 在最后添加