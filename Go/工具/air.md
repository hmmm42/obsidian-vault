```toml
# Air 热重载工具的 TOML 格式配置文件 
# 完整文档参考：https://github.com/air-verse/air 

# 工作目录
# 支持相对路径（.）或绝对路径，注意后续目录必须在此目录下 
root = "."
# air 执行过程中产生的临时文件存储目录 
tmp_dir = "tmp" 

[build] 
# 构建前执行的命令列表（每项命令按顺序执行） 
pre_cmd = ["echo 'hello air' > pre_cmd.txt"] 
# 主构建命令（支持常规 shell 命令或 make 工具） 
cmd = "go build -o ./tmp/main ." 
# 构建后执行的命令列表（相当于按 ^C 程序终止后触发）
post_cmd = ["echo 'hello air' > post_cmd.txt"] 
# 从 `cmd` 编译生成的二进制文件路径 
bin = "tmp/main" 
# 自定义运行参数（可设置环境变量） 
full_bin = "APP_ENV=dev APP_USER=air ./tmp/main" 
# 传递给二进制文件的运行参数（示例将执行 './tmp/main hello world'）
args_bin = ["hello", "world"]
# 监听以下扩展名的文件变动
include_ext = ["go", "tpl", "tmpl", "html"]
# 排除监视的目录列表 
exclude_dir = ["assets", "tmp", "vendor", "frontend/node_modules"] 
# 指定要监视的目录（空数组表示自动检测）
include_dir = [] 
# 指定要监视的特定文件（空数组表示自动检测） 
include_file = []
# 排除监视的特定文件（空数组表示不过滤） 
exclude_file = [] 
# 通过正则表达式排除文件（示例排除所有测试文件）
exclude_regex = ["_test\\.go"] 
# 是否排除未修改的文件（提升性能） 
exclude_unchanged = true 
# 是否跟踪符号链接目录，允许 Air 跟踪符号链接（软链接）指向的目录/文件变化，适用于项目依赖外部符号链接资源的场景 
follow_symlink = true 
# 日志文件存储路径（位于 tmp_dir 下） 
log = "air.log"
# 是否使用轮询机制检测文件变化（替代 fsnotify），Air 默认使用的跨平台文件监控库（基于 Go 的 fsnotify 包），通过操作系统事件实时感知文件变化 
poll = false 
# 轮询检测间隔（默认最低 500ms）
poll_interval = 500 # ms 
# 文件变动后的延迟构建时间（防止高频触发）
delay = 0 # ms
# 构建出错时是否终止旧进程 
stop_on_error = true 
# 是否发送中断信号再终止进程（Windows 不支持） 
send_interrupt = false 
# 发送中断信号后的终止延迟 
kill_delay = 500 # nanosecond 
# 当程序退出时，是否重新运行二进制文件（适合 CLI 工具）
rerun = false 
# 重新运行的时间间隔 
rerun_delay = 500 

[log] 
# 是否显示日志时间戳 time = false 
# 仅显示主日志（过滤监控/构建/运行日志） 
main_only = false 
# 禁用所有日志输出 
silent = false [color] 
# 主日志颜色（支持 ANSI 颜色代码） 
main = "magenta" 
# 文件监控日志颜色
watcher = "cyan" 
# 构建过程日志颜色
build = "yellow" 
# 运行日志颜色 
runner = "green" 

[misc] 
# 退出时自动清理临时目录（tmp_dir） 
clean_on_exit = true 

[screen] 
# 重建时清空控制台界面 
clear_on_rebuild = true 
# 保留滚动历史（不清屏时有效） 
keep_scroll = true 

[proxy] 
# 启用浏览器实时重载功能 
# 参考：https://github.com/air-verse/air/tree/master?tab=readme-ov-file#how-to-reload-the-browser-automatically-on-static-file-changes enabled = true 
# 代理服务器端口（Air 监控端口），浏览器连接到 proxy_port，Air 将请求转发到应用的真实端口 app_port 
proxy_port = 8090 
# 应用实际运行端口（需与业务代码端口一致） 
app_port = 8080
```

