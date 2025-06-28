```go
func main() {
	s := "apple"
	p := &s // p 是一个指向字符串 "apple" 的指针
	
	defer func(s string) {
		fmt.Println("origin s1:", s) // 输出: apple
	}(s)
	
	defer func() {
		fmt.Println("s1:", s) // 输出: orange
	}()
	
	// 写法一：传入参数
	defer func(ptr *string) {
		fmt.Println("传入参数:", *ptr) // 输出: orange
	}(p)
	
	// 写法二：闭包捕获
	defer func() {
		fmt.Println("闭包捕获:", *p) // 输出: orange
	}()
	
	defer func(s string) {
		fmt.Println("origin s2:", s) // 输出: apple
	}(s)
	
	defer func() {
		fmt.Println("s2:", s) // 输出: orange
	}()
	
	// 在 defer 之后，修改了指针 p 指向的内容
	s = "orange"
	
	defer func() {
		fmt.Println("s3:", s) // 输出: orange
	}()
	
}


```

```go
for i := 0; i < 3; i++ {
    defer func() { fmt.Println(i) }() 
    // 2 1 0
}

for i := 0; i < 3; i++ {
    defer func(n int) { fmt.Println(n) }(i)
    // 2 1 0
}
```