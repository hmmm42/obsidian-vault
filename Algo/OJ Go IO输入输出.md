# 少量数据
`fmt.Scan` + `fmt.Println`
```go
package main

import (
	"fmt"
)

func main() {
	var t, n, a int
	fmt.Scan(&t)
	for ; t > 0; t-- {
		fmt.Scan(&n)
		sum := 0
		for i := 0; i < n; i++ {
			fmt.Scan(&a)
			sum += a
		}
		fmt.Println(sum)
	}
}

```
# 大量数据
统一用`reader.ReadString`加`strings.TrimSpace`
不用`reader.ReadLine`, 会有各种问题
```go
package main

import (
	"bufio"
	"fmt"
	"os"
	"strconv"
	"strings"
)

var reader *bufio.Reader

func init() {
	reader = bufio.NewReader(os.Stdin)
	writer = bufio.NewWriter(os.Stdout)
}

func readInt() int {
	line, _ := reader.ReadString('\n')
	num, _ := strconv.Atoi(strings.TrimSpace(line))
	return num
}

func readInts() []int {
	line, _ := reader.ReadString('\n')
	strs := strings.Fields(strings.TrimSpace(line))
	nums := make([]int, len(strs))
	for i := 0; i < len(strs); i++ {
		nums[i], _ = strconv.Atoi(strs[i])
	}
	return nums
}

func readString() string {
	line, _ := reader.ReadString('\n')
	return strings.TrimSuffix(line, "\n")
}

func readBytes() []byte {
	line, _ := reader.ReadBytes('\n')
	return line[:len(line)-1]
}

var writer *bufio.Writer

func main() {
	defer writer.Flush()
	// fmt.Fprintln(writer, )
}
```
# 小数
少量数据可继续用`fmt.Scan`
大量数据:
```go
var reader *bufio.Reader = bufio.NewReader(os.Stdin)
var writer *bufio.Writer = bufio.NewWriter(os.Stdout)

func readFloat() float64 {
	line, _ := reader.ReadString('\n')
	num, _ := strconv.ParseFloat(strings.TrimSpace(line), 64) // 64 表示 float64
	return num
}
```
输出:
```go
func main() {
	defer writer.Flush()

	pi := 3.1415926535
	e := 2.71828

	// 保留 2 位小数
	fmt.Printf("%.2f\n", pi)   // 输出: 3.14
	fmt.Fprintf(writer, "%.2f\n", e) // 输出到 writer: 2.72 (会四舍五入)

	// 保留 4 位小数
	fmt.Printf("%.4f\n", pi)   // 输出: 3.1416
	fmt.Fprintf(writer, "%.4f\n", e) // 输出到 writer: 2.7183

	// 保留 0 位小数（相当于取整）
	fmt.Printf("%.0f\n", pi)   // 输出: 3
	fmt.Fprintf(writer, "%.0f\n", e) // 输出到 writer: 3

	// 指定宽度和精度
	fmt.Printf("%8.3f\n", pi)  // 输出:    3.142 (总宽度为 8，保留 3 位小数)
	fmt.Fprintf(writer, "%8.3f\n", e) // 输出到 writer:    2.718
}
```
# 补充前导零
```go
fmt.Fprintf(writer, "%09d", n)
```
- `0`: 表示如果输出的数字位数不足指定宽度，则在前面填充零。
- `9`: 表示输出的数字至少要占据 9 个字符的宽度。