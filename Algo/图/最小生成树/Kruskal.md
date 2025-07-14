核心思想: 先排序, 再用[[并查集]]组装

[最小生成树_牛客题霸_牛客网](https://www.nowcoder.com/practice/735a34ff4672498b95660f43b7fcd628?tpId=308&tqId=1292435&sourceUrl=%2Fexam%2Foj%3Fpage%3D1%26tab%3D%25E7%25AE%2597%25E6%25B3%2595%25E7%25AF%2587%26topicId%3D308)
```go
func miniSpanningTree( n int ,  m int ,  cost [][]int ) (res int) {
  // union find
  par := make([]int, n+1)
  for i := range par {
    par[i] = i
  }
  var find func(x int)int
  find = func(x int) int {
    if par[x] != x {
      par[x] = find(par[x])
    }
    return par[x]
  }

  sort.Slice(cost, func(i, j int)bool{
    return cost[i][2] < cost[j][2]
  })  

  cnt := 0
  for _, a := range cost {
    x, y, c := a[0], a[1], a[2]
    if find(x) == find(y) {
      continue
    }

    par[par[x]] = par[y]
    res += c
    cnt++
    if cnt == n-1 {
      return
    }
  }
  return
}
```