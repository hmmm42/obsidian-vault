分别枚举每一行的皇后可以放在哪里
```go
func solveNQueens(n int) [][]string {
	var res [][]string
	board := make([][]byte, n)
	for i := range board {
		board[i] = []byte(strings.Repeat(".", n))
	}

	var backtrack func(row int)
	backtrack = func(row int) {
		if row == n {
			var newRes []string
			for _, b := range board {
				newRes = append(newRes, string(b))
			}
			res = append(res, newRes)
			return
		}

		loop:
		for col := range n {
			for i := range row {
				if board[i][col] == 'Q' {
					continue loop
				}
			}
			
			for nr, nc := row, col; nr >= 0 && nc >= 0; nr, nc = nr-1, nc-1 {
				if board[nr][nc] == 'Q' {
					continue loop
				}
			}
			for nr, nc := row, col; nr >= 0 && nc < n; nr, nc = nr-1, nc+1 {
				if board[nr][nc] == 'Q' {
					continue loop
				}
			}
			board[row][col] = 'Q'
			backtrack(row+1)
			board[row][col] = '.'
		}
	}
	backtrack(0)
	return res
}



```