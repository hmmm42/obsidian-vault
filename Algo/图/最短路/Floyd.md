==多源最短路径, 可以处理负权边==
动态规划, 思路类似[[背包问题]]
```go
// f[k][i][j] 表示只经过节点 0->k, i 到 j 的最短路长度
for k := range n {
	for i := range n {
		for j := range n {
			f[k][i][j] = min(f[k - 1][i][j], f[k - 1][i][k] + f[k - 1][k][j])
		}
	}
}
```
状态压缩:
```go
for k := range n {
	for i := range n {
		for j := range n {
			f[i][j] = min(f[i][j], f[i][k] + f[k][j])
		}
	}
}
```