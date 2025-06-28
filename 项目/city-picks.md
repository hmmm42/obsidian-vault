- [Go语言实现黑马点评项目_黑马点评go-CSDN博客](https://blog.csdn.net/m0_57408211/article/details/137934662)
- [lhpqaq/xzdp-go: golang 版本小众点评（黑马点评） 后端](https://github.com/lhpqaq/xzdp-go/tree/master)

# 踩坑
## viper 读取环境变量
好像无法直接将环境变量Unmarshal到结构体中, 需要手动viper.Get(...)
## 日志无法输出
问题的根本原因是 [.envrc](vscode-file://vscode-app/c:/Users/qiuji/AppData/Local/Programs/Microsoft%20VS%20Code/resources/app/out/vs/code/electron-sandbox/workbench/workbench.html) 文件使用了 Windows 风格的行结束符（CRLF，即 `\r\n`），导致环境变量 `LOCAL_ENV` 的值变成了 `"true\r"` 而不是 `"true"`。当 Go 代码中的 [strconv.ParseBool()](vscode-file://vscode-app/c:/Users/qiuji/AppData/Local/Programs/Microsoft%20VS%20Code/resources/app/out/vs/code/electron-sandbox/workbench/workbench.html) 尝试解析这个值时失败了，所以 [isLocal](vscode-file://vscode-app/c:/Users/qiuji/AppData/Local/Programs/Microsoft%20VS%20Code/resources/app/out/vs/code/electron-sandbox/workbench/workbench.html) 变量被设置为 `false`，导致日志器使用了文件输出而不是控制台输出。

**解决方法：** 使用 `sed -i 's/\r$//' .envrc` 命令移除了回车符，然后运行 `direnv allow` 重新加载环境变量。

但是文件中同样找不到输出, 结果是修改文件结果时, 忘记在配置中调整了, 输出到了目录的上一级

**Shell脚本**：
- 如果您的项目中有 `.sh` 脚本，并且是在Windows环境下编辑保存为`\r\n`格式，那么当您尝试在Linux或macOS环境下执行它时，会因为多余的`\r`字符而报错，常见的错误是 `^M: command not found`。
## 测试文件读取统计变量
**测试代码和实际服务运行在不同的进程中**。
当你运行测试时：
1. 测试代码通过 HTTP 请求访问运行在 `localhost:14530` 的服务
2. 服务代码在一个独立的进程中运行，有自己的 [requestCount](vscode-file://vscode-app/c:/Users/qiuji/AppData/Local/Programs/Microsoft%20VS%20Code/resources/app/out/vs/code/electron-sandbox/workbench/workbench.html) 变量
3. 测试代码在另一个进程中运行，有自己的 [requestCount](vscode-file://vscode-app/c:/Users/qiuji/AppData/Local/Programs/Microsoft%20VS%20Code/resources/app/out/vs/code/electron-sandbox/workbench/workbench.html) 变量
4. 两个进程之间的内存是隔离的，所以测试无法访问到服务进程中的


# 架构演进
扁平化架构 -> 三层架构
引入 wire 依赖注入

- **v0.5 (纯数据库)**：解决了基本功能，但有并发安全和性能问题。
- **v0.6 (分布式锁)**：解决了**并发安全**问题，但暴露了**性能**瓶颈。
- **v0.7 (Lua+消息队列)**：通过异步化和内存计算，同时解决了**并发安全**和**性能**问题，达到了生产级秒杀系统的架构水平。