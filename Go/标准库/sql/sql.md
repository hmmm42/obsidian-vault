#  Golang sql 标准库源码解析  
原创 小徐先生1212  小徐先生的编程世界   2023-10-11 09:07  
  
# 0 前言  
  
近期和大家一起探讨 go 语言中关系型数据库有关的话题.  
  
本系列会拆分为多个篇章：  
- • **database/sql 库研究：** 研究 go 语言 sql 标准库下对数据库连接池的实现细节，以及对数据库驱动模块的接口定义规范  
  
- • **mysql driver 库研究：** 研究 go 语言下 mysql 数据库驱动的底层实现细节，对应开源地址：https://github.com/go-sql-driver/mysql  
  
- • **orm 框架 gorm 库研究：** 研究 go 语言最流行的 orm 框架——gorm 的实现原理，对应开源地址：https://github.com/go-gorm/gorm  
  
   
  
本文是其中的第一篇，走读的 **database/sql 源码统一为 go v1.19 版本**.   
  
有关 database/sql 库的使用教程可以参见：http://go-database-sql.org/index.html  
  
涉及到的源码文件目录为：  
  
<table><thead style="line-height: 1.75;background: rgba(0, 0, 0, 0.05);font-weight: bold;color: rgb(63, 63, 63);"><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;"><strong style="line-height: 1.75;color: rgb(15, 76, 129);">内容</strong></td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;"><strong style="line-height: 1.75;color: rgb(15, 76, 129);">文件</strong></td></tr></thead><tbody><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">sql 库主流程</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">database/sql/sql.go</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">数据库驱动相关</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">database/sql/driver/driver.go</td></tr></tbody></table>  


	
本文分享大纲如下：  
  
![](https://mmbiz.qpic.cn/sz_mmbiz_png/3ic3aBqT2ibZtPtCJOAEicA4Ou42m8gOFjVdSJqMibgZl4P47pZQLqmBlBhicyXcIUznOb3F4AIDs2IQNfI3Kqw3iabA/640?wx_fmt=png "")  
  
   
# 1 简易教程  
  
首先通过一个简单的交互场景，向大家展示一下如何基于标准库 database/sql 完成一笔关系型数据库的查询操作，场景如下：  
- • **注册数据库驱动：** 使用数据库类型为 mysql，通过匿名导入 package:github.com/go-sql-driver/mysql，在该 pkg 的 init 函数中完成驱动的注册操作（这部分内容将在下期展开）  
  
- • **定义数据模型：** 创建一个 user 表，里面包含一个 int64 类型的 userID 字段  
  
- • **创建数据库实例：** 调用 database/sql 库的 Open 方法，填入 mysql 的 dsn（包含用户名、密码、ip、端口、数据库名等信息），完成数据库实例创建 **（注意：sql.Open 方法只创建db 实例，还未执行任何连接操作，如需测试网络、鉴权等信息，可以调用 ping 方法）**  
  
- • **执行查询 sql：** 调用 db.QueryRowContext，执行 sql，并通过 row 返回结果  
  
- • **解析查询结果：** 调用 row.Scan 方法，解析查询结果赋值给 user 实例  
  
   
  
该流程对应的代码展示如下：  
```
import (
    "context"
    "database/sql"
    "testing"


    // 注册 mysql 数据库驱动
    _ "github.com/go-sql-driver/mysql"
)


type user struct {
    UserID int64
}


func Test_sql(t *testing.T) {
    // 创建 db 实例
    db, err := sql.Open("mysql", "username:passpord@(ip:port)/database")
    if err != nil {
        t.Error(err)
        return
    }
    
    // 执行 sql
    ctx := context.Background()
    row := db.QueryRowContext(ctx, "SELECT user_id FROM user WHERE ORDER BY created_at DESC limit 1")
    if row.Err() != nil {
        t.Error(err)
        return
    }


    // 解析结果
    var u user
    if err = row.Scan(&u.UserID); err != nil {
        t.Error(err)
        return
    }
    t.Log(u.UserID)
}
```  
  
   
  
下面我们以这个使用示例的代码作为源码走读的入口，深入到 database/sql 标准库的底层实现细节当中.  
  
   
# 2 核心类定义  
## 2.1 抽象接口定义  
  
标准库 database/sql 定义了 go 语言通用的结构化查询流程框架，其对接的数据库类型是灵活多变的，如 mysql、sqlite、oracle 等. 因此**在 database/sql 中，与具体数据库交互的细节内容统一托付给一个抽象的数据库驱动模块，在其中声明好一套适用于各类关系型数据库的统一规范，将各个关键节点定义成抽象的 interface，由具体类型的数据库完成数据库驱动模块的实现**，然后将其注入到 database/sql 的大框架之中.  
  
   
  
database/sql 关于数据库驱动模块下各核心 interface 主要包括：  
- • **Connector：抽象的数据库连接器**，需要具备创建数据库连接以及返回从属的数据库驱动的能力  
  
- • **Driver：抽象的数据库驱动**，具备创建数据库连接的能力  
  
- • **Conn：抽象的数据库连接**，具备预处理 sql 以及开启事务的能力  
  
- • **Tx：抽象的事务**，具备提交和回滚的能力  
  
- • **Statement：抽象的请求预处理状态**. 具备实际执行 sql 并返回执行结果的能力  
  
- • **Result/Row：** 抽象的 sql 执行结果  
  
   
  
其上各 interface 之间的依赖拓扑关系如下图所示：  
  
![](https://mmbiz.qpic.cn/sz_mmbiz_png/3ic3aBqT2ibZtPtCJOAEicA4Ou42m8gOFjVwkK88SE5icKOjmwkXjl1jhhQKm5QOTJ2ItvBmE9MoibcJkRYDI4mb4KQ/640?wx_fmt=png "")  
  
   
  
下面展示一下具体的实现代码，这部分内容主要位于 database/sql/driver/driver.go 文件中.  
  
**I 抽象的数据库连接器**  
  
由具体的数据库类型提供具体的实现版本  
```
type Connector interface {
    // 获取一个数据库连接
    Connect(context.Context) (Conn, error)


    // 获取数据库驱动
    Driver() Driver
}
```  
  
   
  
**II 抽象的数据库连接**  
  
由具体的数据库类型提供具体的实现版本  
```
type Conn interface {
    // 预处理 sql
    Prepare(query string) (Stmt, error)
 
    // 关闭连接   
    Close() error


    // 开启事务
    Begin() (Tx, error)
}
```  
  
   
  
**III 抽象的请求预处理状态**  
  
由具体的数据库类型提供具体的实现版本  
```
type Stmt interface {
    // 关闭
    Close() error


    // 返回 sql 中存在的可变参数数量
    NumInput() int


    // 执行操作类型的 sql
    Exec(args []Value) (Result, error)




    // 执行查询类型的 sql
    Query(args []Value) (Rows, error)
}
```  
  
   
  
**IV 抽象的执行结果**  
  
由具体的数据库类型提供具体的实现版本  
```
// Result is the result of a query execution.
type Result interface {
    // 最后一笔插入数据的主键
    LastInsertId() (int64, error)


    // 操作影响的行数
    RowsAffected() (int64, error)
}
```  
  
   
```
type Rows interface {
    // 返回所有列名
    Columns() []string


    // 关闭 rows 迭代器
    Close() error


    // 遍历
    Next(dest []Value) error
}
```  
  
   
  
**V 抽象的事务**  
  
由具体的数据库类型提供具体的实现版本  
```
// Tx is a transaction.
type Tx interface {
    // 提交事务
    Commit() error
    // 回滚事务
    Rollback() error
}
```  
  
   
  
**VI 抽象的数据库驱动**  
  
由具体的数据库类型提供具体的实现版本  
```
type Driver interface {
    // 开启一个新的数据库连接
    Open(name string) (Conn, error)
}
```  
  
   
## 2.2 实体类定义  
  
下面展示一下 database/sql 库定义的几个核心实体类. 核心内容主要是对于数据库连接池的实现以及对第三方数据库驱动能力的再封装.  
  
   
  
**I 数据库**  
  
其中最核心的类是 database/sql/sql.go 文件中的 DB，对应为数据库的具象化实例，其中包含如下几个核心字段：  
- • connector：用于创建数据库连接的抽象连接器，由第三方数据库提供具体实现  
  
- • mu：互斥锁，保证并发安全  
  
- • freeConn：数据库连接池，缓存可用的连接以供后续复用  
  
- • connRequests：唤醒通道集合，和阻塞等待连接的协程是一对一的关系  
  
- • openerCh：创建连接信号通道. 用于向连接创建协程 opener goroutine 发送信号  
  
- • stop：连接创建协程 opener goroutine 的终止器，用于停止该协程  
  
   
  
db 类非常核心，其示意图展示如下：  
  
![](https://mmbiz.qpic.cn/sz_mmbiz_png/3ic3aBqT2ibZtPtCJOAEicA4Ou42m8gOFjV0icN1uTUBibpDaurB5rhldOgA4kaPzSRdo15GyuEtQRTdWsUmSslGvuA/640?wx_fmt=png "")  
  
   
  
除此之外， db 类中还包含了一系列配置参数，如 maxIdleCount、maxOpen 等. 完整的内容可参见下面的代码及注释：  
```
type DB struct {
    // 所有 goroutine 阻塞等待数据库连接的总等待时长
    waitDuration int64 
    
    // 指定数据库驱动用于生成连接的连接器
    connector driver.Connector
    
    // 已关闭的连接总数
    numClosed uint64


    // 互斥锁保证 db 实例并发安全
    mu           sync.Mutex    
    
    // 可用的数据库连接，及本质意义上的连接池. 其中连接按照创建/归还时间正序排列
    freeConn     []*driverConn 
    
    // 存储了所有用于唤醒阻塞等待连接的 goroutine 的 channel
    connRequests map[uint64]chan connRequest
    
    // 维护了一个全局递增的计数器，作为 connRequests 中的 key
    nextRequest  uint64 
    
    // 已开启使用或等待使用的连接数量
    numOpen      int   
    
    // 用于向 opener 传递创建连接信号的 chan
    openerCh          chan struct{}
    
    // 标识数据库是否已关闭  
    closed            bool
    
    // 在关闭数据库前，进行依赖梳理
    dep               map[finalCloser]depSet
    
    // 最大空闲连接数. 若设置为 0，则取默认值 2；若设置为负值，则取 0，代表不启用连接池
    maxIdleCount      int       
              
    // 最多可以打开的连接数. 若设为非正值，则代表不作限制
    maxOpen           int      
               
    // 一个连接最多可以使用多长时间
    maxLifetime       time.Duration          
    
    // 一个空闲连接最多可以存在多长时间
    maxIdleTime       time.Duration          
    
    // 用于向 cleaner 传递清理连接信号的 chan
    cleanerCh         chan struct{
      
    // 有多少 goroutine 在阻塞等待连接
    waitCount         int64 
    
    // 总共有多少空闲连接被关闭了 
    maxIdleClosed     int64 
    
    // 所有因为 maxIdleTime 被关闭的连接的总闲置时长
    maxIdleTimeClosed int64 
    
    // 所有因为 maxLifetime 被关闭的连接的总生存时长
    maxLifetimeClosed int64


    // 用于终止 opener 的控制器
    stop func() 
}
```  
  
   
  
**II 数据库连接**  
  
下面是 database/sql 中封装的数据库连接类 driverConn，其核心属性是由第三方驱动实现的 driver.Conn，在此之上添加了时间属性、回调函数、状态标识等辅助信息. 具体内容参见下面的代码：  
```
type driverConn struct {
    // 该连接所属的 db 实例
    db        *DB
    // 该连接被创建出来的时间
    createdAt time.Time


    // 连接粒度的互斥锁
    sync.Mutex  
    
    // 真实的数据库连接. 由第三方驱动实现
    ci          driver.Conn
    
    // 连接使用前，是否需要对会话进行重置
    needReset   bool 
    
    // 连接是否处于关闭流程
    closed      bool
    // 连接是否已最终关闭
    finalClosed bool 
    
    // 该连接下所有的 statement
    openStmt    map[*driverStmt]bool


    // 该连接是否正在被使用
    inUse      bool
    
    // 该连接被放回连接池的时间
    returnedAt time.Time 
    
    // 连接被放回连接池时的回调函数
    onPut      []func() 
    
    // 连接是否已关闭，作用和 closed 相同
    dbmuClosed bool     
}
```  
  
   
  
**III 请求预处理状态**  
  
在抽象的 driver.Stmt 基础上，添加了互斥锁、关闭状态标识等信息.  
```
type driverStmt struct {
    // 锁
    sync.Locker 
    // 真正的 statement，由第三方数据库驱动实现
    si          driver.Stmt
    // statement 是否已关闭
    closed      bool
    // statement 关闭操作返回的错误
    closeErr    error 
}
```  
  
   
  
**IV 事务**  
  
在抽象的 driver.TX 基础上，额外添加了互斥锁、数据库连接、连接释放函数、上下文等辅助属性.  
```
// 事务
type Tx struct {
    // 从属的数据库
    db *DB


    // closemu prevents the transaction from closing while there
    // is an active query. It is held for read during queries
    // and exclusively during close.
    closemu sync.RWMutex


    // 从属的数据库连接
    dc  *driverConn
    
    // 真正的事务实体，由第三方驱动实现
    txi driver.Tx


    // releaseConn is called once the Tx is closed to release
    // any held driverConn back to the pool.
    releaseConn func(error)


    // 事务是否已完成
    done int32


    // keepConnOnRollback is true if the driver knows
    // how to reset the connection's session and if need be discard
    // the connection.
    keepConnOnRollback bool


    // 当前事务下包含的所有 statement
    stmts struct {
        sync.Mutex
        v []*Stmt
    }


    // 控制事务生命周期的终止器
    cancel func()


    // 控制事务生命周期的 context
    ctx context.Context
}
```  
  
至此，我们介绍完了 database/sql 库下各个核心类，从下一章开始，我们进入几个核心方法链路的源码走读环节.  
  
   
# 3 创建数据库对象  
  
首先我们沿着 sql.Open 方法向下追溯，查看一下创建数据库实例的流程细节.  
  
![](https://mmbiz.qpic.cn/sz_mmbiz_png/3ic3aBqT2ibZtPtCJOAEicA4Ou42m8gOFjVFOiaJ7IyL7D67yUGNNWYPO7U62cTibtJhTdX8hJzBwmcL28x8ibouZibBQ/640?wx_fmt=png "")  
## 3.1 创建数据库  
  
Open 方法是创建 db 实例的入口方法：  
- • 首先校验对应的 driver 是否已注册  
  
- • 接下来调用 OpenDB 方法执行真正的 db 实例创建操作  
  
```
// 创建数据库
func Open(driverName, dataSourceName string) (*DB, error) {
    // 首先根据驱动类型获取数据库驱动
    driversMu.RLock()
    driveri, ok := drivers[driverName]
    driversMu.RUnlock()
    if !ok {
        return nil, fmt.Errorf("sql: unknown driver %q (forgotten import?)", driverName)
    }


    // 若驱动实现了对应的连接器 connector，则获取之并进行 db 实例创建
    if driverCtx, ok := driveri.(driver.DriverContext); ok {
        connector, err := driverCtx.OpenConnector(dataSourceName)
        if err != nil {
            return nil, err
        }
        return OpenDB(connector), nil
    }


    // 默认使用 dsn 数据库连接器，进行 db 创建
    return OpenDB(dsnConnector{dsn: dataSourceName, driver: driveri}), nil
}
```  
  
   
  
在 OpenDB 方法中：  
- • 首先创建一个 db 实例  
  
- • 接下来启动一个 connectionOpener 协程，用于在连接池资源不足时，补充创建连接  
  
- • 在启动 connectionOpener 时会注入一个 context，并通过 db.stop 进行协程终止  
  
```
func OpenDB(c driver.Connector) *DB {
    ctx, cancel := context.WithCancel(context.Background())
    db := &DB{
        connector:    c,
        openerCh:     make(chan struct{}, connectionRequestQueueSize),
        lastPut:      make(map[*driverConn]string),
        connRequests: make(map[uint64]chan connRequest),
        stop:         cancel,
    }


    go db.connectionOpener(ctx)


    return db
}
```  
  
   
## 3.2 连接创建器  
  
在 connectionOpener 方法中，通过 for + select 多路复用的形式，保持协程的运行.  
  
每当接收到来自 openerCh 的信号后，会调用 openNewConnection 方法进行连接的补充创建  
```
// 该方法是异步启动的常驻 goroutine，当 db.stop 方法被调用后，ctx 会被终止，此时 goroutine 才会退出
func (db *DB) connectionOpener(ctx context.Context) {
    for {
        select {
        case <-ctx.Done():
            return
        // 通过 openerCh 接收到信号，进行连接创建操作
        case <-db.openerCh:
            db.openNewConnection(ctx)
        }
    }
}
```  
  
在 openNewConnection 方法中，会调用第三方驱动 connector 创建出新的数据库连接，然后将其封装到 driverConn 实例中，并将其补充到连接池 freeConn 当中.  
```
// Open one new connection
func (db *DB) openNewConnection(ctx context.Context) {
    // 调用第三方驱动 connector，创建一笔新的数据库连接
    ci, err := db.connector.Connect(ctx)
    db.mu.Lock()
    defer db.mu.Unlock()
    if db.closed {
        if err == nil {
            ci.Close()
        }
        db.numOpen--
        return
    }
    if err != nil {
        db.numOpen--
        db.putConnDBLocked(nil, err)
        db.maybeOpenNewConnections()
        return
    }
    // 创建出一笔新的连接
    dc := &driverConn{
        db:         db,
        createdAt:  nowFunc(),
        returnedAt: nowFunc(),
        ci:         ci,
    }
    
    // 将连接添加到连接池中
    if db.putConnDBLocked(dc, err) {
        db.addDepLocked(dc, dc)
    } else {
        db.numOpen--
        ci.Close()
    }
}
```  
  
   
# 4 执行请求流程  
  
在本章中，我们将视角放在执行一次 db.Query() 请求的全流程中，该链路宏观流程图如下所示：  
  
![](https://mmbiz.qpic.cn/sz_mmbiz_png/3ic3aBqT2ibZtPtCJOAEicA4Ou42m8gOFjVibciaEl663YPgnDuF2leFibq7AKeuNVia9pdlWVjSs8iayZ5VG7nAKIGlNw/640?wx_fmt=png "")  
  
其中核心步骤包括：  
- • **获取数据库连接**：通过调用 conn 方法完成  
  
- • **执行 sql**：通过调用 queryDC 方法完成  
  
- • **归还/释放连接：** 通过在 queryDC 方法中调用 releaseConn 方法完成  
  
   
## 4.1 入口方法  
  
在调用 db.QueryContext 方法时，会通过 for 循环建立有限的请求重试机制. 这是因为在请求过程中，可能会因为连接过期而导致发生偶发性的 ErrBadConn 错误，针对这种错误，可以采用重试的方式来提高请求的成功率.  
  
从 QueryContext 方法中可以看出，在采用连接池策略执行请求过程中，连续遇到两次 ErrBadConn 之后，会将策略调整为不采用连接池直接新建连接的方式，再兜底执行一次请求.  
```
const maxBadConnRetries = 2


// 执行查询类 sql 
func (db *DB) QueryContext(ctx context.Context, query string, args ...any) (*Rows, error) {
    var rows *Rows
    var err error
    var isBadConn bool
    
    // 最多可以因为 BadConn 类型的错误重试两次
    for i := 0; i < maxBadConnRetries; i++ {
        // 执行 sql，此时采用的是 连接池有缓存连接优先复用 的策略
        rows, err = db.query(ctx, query, args, cachedOrNewConn)
        // 属于 badConn 类型的错误可以重试
        isBadConn = errors.Is(err, driver.ErrBadConn)
        if !isBadConn {
            break
        }
    }
    
    // 重试了两轮 badConn 错误后，第三轮会采用
    if isBadConn {
        return db.query(ctx, query, args, alwaysNewConn)
    }
    return rows, err
}
```  
  
   
  
在 query 方法中，首先会根据对应的策略 strategy 调用 conn 方法获取数据库连接，然后执行 queryDC 方法完成 sql 执行.  
```
// 执行 sql 语句.
func (db *DB) query(ctx context.Context, query string, args []any, strategy connReuseStrategy) (*Rows, error) {
    // 首先获取数据库连接
    dc, err := db.conn(ctx, strategy)
    if err != nil {
        return nil, err
    }


    // 使用数据库连接，执行 sql 语句
    return db.queryDC(ctx, nil, dc, dc.releaseConn, query, args)
}
```  
  
   
## 4.2 获取数据库连接  
  
接下来，我们会重点介绍如何与连接池交互，完成获取连接和归还连接的操作. 与连接池交互流程如下图所示：  
  
![](https://mmbiz.qpic.cn/sz_mmbiz_png/3ic3aBqT2ibZtPtCJOAEicA4Ou42m8gOFjVoelTLlezL2IZjrgqOa6KibnUwoVfnfuFDfNiaplMCBJiaHFEXELK2oVBQ/640?wx_fmt=png "")  
  
   
  
conn 方法的目标是获取一笔可用的数据库连接：  
- • 倘若启用了连接池策略且连接池中有可用的连接，则会优先获取该连接进行返回  
  
- • 倘若当前连接数已达上限，则会将当前协程挂起，建立对应的 channel 添加到 connRequests map 中，等待有连接释放时被唤醒  
  
- • 倘若连接数未达上限，则会调用第三方驱动的 connector 完成新连接的创建  
  
更详细的内容参见下方的代码：  
```go
func (db *DB) conn(ctx context.Context, strategy connReuseStrategy) (*driverConn, error) {
    db.mu.Lock()
    // 倘若数据库已关闭，返回错误
    if db.closed {
        db.mu.Unlock()
        return nil, errDBClosed
    }
    
    // Check if the context is expired.
    select {
    default:
    case <-ctx.Done():
        db.mu.Unlock()
        return nil, ctx.Err()
    }
    lifetime := db.maxLifetime


    // 倘若策略允许使用连接池，则优先获取连接池尾端的连接进行复用
    last := len(db.freeConn) - 1
    if strategy == cachedOrNewConn && last >= 0 {
        // Reuse the lowest idle time connection so we can close
        // connections which remain idle as soon as possible.
        conn := db.freeConn[last]
        db.freeConn = db.freeConn[:last]
        conn.inUse = true
        // 倘若连接已达到最长生存时间，则返回 ErrBadConn，上游会进行重试
        if conn.expired(lifetime) {
            db.maxLifetimeClosed++
            db.mu.Unlock()
            conn.Close()
            return nil, driver.ErrBadConn
        }
        db.mu.Unlock()


        // 倘若策略需要，则会对 conn 进行会话重置
        if err := conn.resetSession(ctx); errors.Is(err, driver.ErrBadConn) {
            conn.Close()
            return nil, err
        }


        return conn, nil
    }


    // 倘若可用连接数达到上限，则当前 goroutine 需要阻塞等待连接释放
    if db.maxOpen > 0 && db.numOpen >= db.maxOpen {
        // 递增 nextRequestKey，将唤醒当前 goroutine 的 channel 挂载到 db.connRequests map 中 
        req := make(chan connRequest, 1)
        reqKey := db.nextRequestKeyLocked()
        db.connRequests[reqKey] = req
        db.waitCount++
        db.mu.Unlock()


        waitStart := nowFunc()


        // 通过 select + 读 chan 操作，令当前 goroutine 陷入阻塞. 只有 context 终止，或者有连接通过 chan 投递过来时，当前 goroutine 才会被唤醒
        select {
        // 当前 goroutine 生命周期已终止
        case <-ctx.Done():
            // 从 connRequest 中移除当前 goroutine 对应的 chan
            db.mu.Lock()
            delete(db.connRequests, reqKey)
            db.mu.Unlock()




            atomic.AddInt64(&db.waitDuration, int64(time.Since(waitStart)))


            // double check： 倘若在移除 chan 前恰好有连接投递过来，则将其放回到连接池中
            select {
            default:
            case ret, ok := <-req:
                if ok && ret.conn != nil {
                    db.putConn(ret.conn, ret.err, false)
                }
            }
            return nil, ctx.Err()
        // 通过 channel 接收到释放的连接
        case ret, ok := <-req:
            atomic.AddInt64(&db.waitDuration, int64(time.Since(waitStart)))


            if !ok {
                return nil, errDBClosed
            }
           
            // 倘若该连接恰好达到最长生存时间，则关闭连接，返回 ErrBadConn，由上游进行重试
            if strategy == cachedOrNewConn && ret.err == nil && ret.conn.expired(lifetime) {
                db.mu.Lock()
                db.maxLifetimeClosed++
                db.mu.Unlock()
                ret.conn.Close()
                return nil, driver.ErrBadConn
            }
            // 倘若连接为空，代表投递连接时发生错误，返回对应的错误
            if ret.conn == nil {
                return nil, ret.err
            }


            // 如有必要，对连接进行会话重置
            if err := ret.conn.resetSession(ctx); errors.Is(err, driver.ErrBadConn) {
                ret.conn.Close()
                return nil, err
            }
            // 返回从连接池中获取到的连接进行复用
            return ret.conn, ret.err
        }
    }


    // 未命中连接池策略，则通过 driver connector 创建新的连接，并返回
    db.numOpen++ 
    db.mu.Unlock()
    ci, err := db.connector.Connect(ctx)
    if err != nil {
        db.mu.Lock()
        db.numOpen-- // correct for earlier optimism
        db.maybeOpenNewConnections()
        db.mu.Unlock()
        return nil, err
    }
    db.mu.Lock()
    dc := &driverConn{
        db:         db,
        createdAt:  nowFunc(),
        returnedAt: nowFunc(),
        ci:         ci,
        inUse:      true,
    }
    db.addDepLocked(dc, dc)
    db.mu.Unlock()
    return dc,nil
}
```  
  
   
## 4.3 执行请求  
  
在 queryDC 方法中，会依赖于第三方驱动完成请求的执行：  
- • 首先通过连接将 sql 预处理成 statement  
  
- • 执行请求，并返回对应的结果  
  
- • 最后需要将连接放回连接池，倘若连接池已满或者连接已过期，则需要关闭连接  
  
```go
func (db *DB) queryDC(ctx, txctx context.Context, dc *driverConn, releaseConn func(error), query string, args []any) (*Rows, error) {
    queryerCtx, ok := dc.ci.(driver.QueryerContext)
    var queryer driver.Queryer
    if !ok {
        queryer, ok = dc.ci.(driver.Queryer)
    }
    if ok {
        var nvdargs []driver.NamedValue
        var rowsi driver.Rows
        var err error
        withLock(dc, func() {
            nvdargs, err = driverArgsConnLocked(dc.ci, nil, args)
            if err != nil {
                return
            }
            rowsi, err = ctxDriverQuery(ctx, queryerCtx, queryer, query, nvdargs)
        })
        if err != driver.ErrSkip {
            if err != nil {
                releaseConn(err)
                return nil, err
            }
            // Note: ownership of dc passes to the *Rows, to be freed
            // with releaseConn.
            rows := &Rows{
                dc:          dc,
                releaseConn: releaseConn,
                rowsi:       rowsi,
            }
            rows.initContextClose(ctx, txctx)
            return rows, nil
        }
    }


    var si driver.Stmt
    var err error
    withLock(dc, func() {
        si, err = ctxDriverPrepare(ctx, dc.ci, query)
    })
    if err != nil {
        releaseConn(err)
        return nil, err
    }


    ds := &driverStmt{Locker: dc, si: si}
    rowsi, err := rowsiFromStatement(ctx, dc.ci, ds, args...)
    if err != nil {
        ds.Close()
        releaseConn(err)
        return nil, err
    }


    // 将获得的结果 rowsi 填充到 Rows 中进行相应
    rows := &Rows{
        dc:          dc,
        releaseConn: releaseConn,
        rowsi:       rowsi,
        closeStmt:   ds,
    }
    rows.initContextClose(ctx, txctx)
    return rows, nil
}
```  
  
   
## 4.4 归还数据库连接  
  
使用完数据库连接后，需要尝试将其放还连接池中，入口方法为 releaseConn.  
```
func (dc *driverConn) releaseConn(err error) {
    dc.db.putConn(dc, err, true)
}
```  
  
   
  
在 putConn 方法中，主要执行了：  
- • 判断连接是否已失效，是的话直接关闭连接  
  
- • 加 db 互斥锁，保证后续与连接池交互操作的并发安全性  
  
- • 执行一系列回调函数  
  
- • 调用 putConnDBLocked 方法将连接放回连接池中  
  
```
func (db *DB) putConn(dc *driverConn, err error, resetSession bool) {
    if !errors.Is(err, driver.ErrBadConn) {
        if !dc.validateConnection(resetSession) {
            err = driver.ErrBadConn
        }
    }
    
    db.mu.Lock()
    if !dc.inUse {
        db.mu.Unlock()     
        panic("sql: connection returned that was never out")
    }


    // 倘若放入的连接已达到最长生存时间，则将错误类型置为 ErrBadConn
    if !errors.Is(err, driver.ErrBadConn) && dc.expired(db.maxLifetime) {
        db.maxLifetimeClosed++
        err = driver.ErrBadConn
    }
    
    dc.inUse = false
    dc.returnedAt = nowFunc()
    
    // 执行连接被放回连接池时的回调函数
    for _, fn := range dc.onPut {
        fn()
    }
    dc.onPut = nil


    // 倘若错误是 ErrBadConn，则关闭该连接. 并判断是否需要往连接池中补充新的连接
    if errors.Is(err, driver.ErrBadConn) {        
        db.maybeOpenNewConnections()
        db.mu.Unlock()
        dc.Close()
        return
    }
    
    if putConnHook != nil {
        putConnHook(db, dc)
    }
    
    // 将连接放回连接池. 该方法在取得数据库锁的前提下执行. 
    added := db.putConnDBLocked(dc, nil)
    db.mu.Unlock()


    if !added {
        dc.Close()
        return
    }
}
```  
  
   
  
在 putConnDBLocked 方法中：  
- • 首先根据 connRequests map 判断是否有协程在等待连接，有的话优先通过 channel 将连接传送给对方，并可以直接返回  
  
- • 其次判断连接池空闲连接数是否已达上限，没有的话则将连接放回连接池中，否则直接释放连接  
  
```
// 连接放回连接池
func (db *DB) putConnDBLocked(dc *driverConn, err error) bool {
    if db.closed {
        return false
    }
    if db.maxOpen > 0 && db.numOpen > db.maxOpen {
        return false
    }
    
    // 倘若存在阻塞等待数据库连接的 goroutine，则从 db.connRequests 随机抽取一个目标，通过 channel 将连接传递给对方
    if c := len(db.connRequests); c > 0 {
        var req chan connRequest
        var reqKey uint64
        for reqKey, req = range db.connRequests {
            break
        }
        delete(db.connRequests, reqKey) // Remove from pending requests.
        if err == nil {
            dc.inUse = true
        }
        req <- connRequest{
            conn: dc,
            err:  err,
        }
        return true
    //  否则将连接放回连接池中
    } else if err == nil && !db.closed {
        if db.maxIdleConnsLocked() > len(db.freeConn) {
            db.freeConn = append(db.freeConn, dc)
            db.startCleanerLocked()
            return true
        }
        db.maxIdleClosed++
    }
    return false
}
```  
  
   
# 5 清理连接流程  
  
最后，在本章中我们来梳理一下，过期的连接会基于怎样的机制得到及时回收的机会.  
## 5.1 启动清理协程  
  
![](https://mmbiz.qpic.cn/sz_mmbiz_png/3ic3aBqT2ibZtPtCJOAEicA4Ou42m8gOFjVWE43MXSRzjTf0V3WQ3gCvR0KY4BLH1eH5UDtWnz3NLqmgapZ0JaA0A/640?wx_fmt=png "")  
  
连接池中过期的连接会通过一个异步的清理协程 cleaner 定期执行清理操作. cleaner 启动的时机分为三处，每次启动前都会实现检查 cleaner 是否存在，保证全局只有一个唯一的 cleaner goroutine：  
- • 用户设置连接最大生存时长时：SetConnMaxLifetime  
  
- • 用户设置连接最大空闲时长时：SetConnMaxIdleTime  
  
- • 有连接被归还回连接池时：putConnDBLocked  
  
对应代码展示如下：  
```
func (db *DB) SetConnMaxLifetime(d time.Duration) {
    if d < 0 {
        d = 0
    }
    db.mu.Lock()
    // Wake cleaner up when lifetime is shortened.
    if d > 0 && d < db.maxLifetime && db.cleanerCh != nil {
        select {
        case db.cleanerCh <- struct{}{}:
        default:
        }
    }
    db.maxLifetime = d
    db.startCleanerLocked()
    db.mu.Unlock()
}
```  
  
   
```
func (db *DB) SetConnMaxIdleTime(d time.Duration) {
    if d < 0 {
        d = 0
    }
    db.mu.Lock()
    defer db.mu.Unlock()




    // Wake cleaner up when idle time is shortened.
    if d > 0 && d < db.maxIdleTime && db.cleanerCh != nil {
        select {
        case db.cleanerCh <- struct{}{}:
        default:
        }
    }
    db.maxIdleTime = d
    db.startCleanerLocked()
}
```  
  
   
```
func (db *DB) putConnDBLocked(dc *driverConn, err error) bool {
    // ...
    if c := len(db.connRequests); c > 0 {
        // ...
    } else if err == nil && !db.closed {
        if db.maxIdleConnsLocked() > len(db.freeConn) {
            // ...
            db.startCleanerLocked()
           // ...
        }
        // ...
    }
    return false
}
```  
  
   
  
在上述三个方法中，无一例外都会通过调用 startCleanerLocked 方法尝试执行 cleaner 的创建：  
```
func (db *DB) startCleanerLocked() {
    if (db.maxLifetime > 0 || db.maxIdleTime > 0) && db.numOpen > 0 && db.cleanerCh == nil {
        db.cleanerCh = make(chan struct{}, 1)
        go db.connectionCleaner(db.shortestIdleTimeLocked())
    }
}
```  
  
   
  
值得一提的是，由于 cleaner 协程存在一个自动扩缩机制：  
- • 在当前存活总连接数为 0 的闲置状态下，cleaner 会主动退出. （5.2 小节的 connectionCleaner 方法中会有所体现）  
  
- • 在有连接被放回连接池时，会尝试重新启动 cleaner. （对应的就是此处的 putConnDBLocked 方法）  
  
   
## 5.2 执行清理任务  
  
![](https://mmbiz.qpic.cn/sz_mmbiz_png/3ic3aBqT2ibZtPtCJOAEicA4Ou42m8gOFjVEPVCKMChMPh9Y16B53icyOILwftz9KCxbia5zGX34MkHaLiaYF9aYLq4Q/640?wx_fmt=png "")  
  
接下来是 cleaner 协程的运行流程，整体是通过 for + select 的方式常驻运行.  
  
其中，cleaner 创建了一个定时器 ticker，定时时间间隔会在 maxIdleTime、maxLifeTime 中取较小值，并基于秒级向上取整.  
  
每一轮 ticker 触发后，会执行：  
- • 判断当前 db 是否已关闭或者存活连接数是否为零，是的话退出当前 cleaner 协程  
  
- • 调用 connectionCleanerRunLocked 对连接池中过期的连接进行清理  
  
```
func (db *DB) connectionCleaner(d time.Duration) {
    const minInterval = time.Second




    if d < minInterval {
        d = minInterval
    }
    t := time.NewTimer(d)




    for {
        select {
        case <-t.C:
        case <-db.cleanerCh: // maxLifetime was changed or db was closed.
        }


        db.mu.Lock()


        d = db.shortestIdleTimeLocked()
        if db.closed || db.numOpen == 0 || d <= 0 {
            db.cleanerCh = nil
            db.mu.Unlock()
            return
        }


        d, closing := db.connectionCleanerRunLocked(d)
        db.mu.Unlock()
        for _, c := range closing {
            c.Close()
        }


        if d < minInterval {
            d = minInterval
        }




        if !t.Stop() {
            select {
            case <-t.C:
            default:
            }
        }
        t.Reset(d)
    }
}
```  
  
   
  
在 connectionCleanerRunLocked 方法中，会分别将达到 maxIdleTime 和 maxLifeTime 的连接从连接池 freeConn 中清除，并把这部分连接返回给上游进行批量关闭操作：  
```
func (db *DB) connectionCleanerRunLocked(d time.Duration) (time.Duration, []*driverConn) {
    var idleClosing int64
    var closing []*driverConn
    if db.maxIdleTime > 0 {
        // As freeConn is ordered by returnedAt process
        // in reverse order to minimise the work needed.
        idleSince := nowFunc().Add(-db.maxIdleTime)
        last := len(db.freeConn) - 1
        for i := last; i >= 0; i-- {
            c := db.freeConn[i]
            if c.returnedAt.Before(idleSince) {
                i++
                closing = db.freeConn[:i:i]
                db.freeConn = db.freeConn[i:]
                idleClosing = int64(len(closing))
                db.maxIdleTimeClosed += idleClosing
                break
            }
        }




        if len(db.freeConn) > 0 {
            c := db.freeConn[0]
            if d2 := c.returnedAt.Sub(idleSince); d2 < d {
                // Ensure idle connections are cleaned up as soon as
                // possible.
                d = d2
            }
        }
    }




    if db.maxLifetime > 0 {
        expiredSince := nowFunc().Add(-db.maxLifetime)
        for i := 0; i < len(db.freeConn); i++ {
            c := db.freeConn[i]
            if c.createdAt.Before(expiredSince) {
                closing = append(closing, c)




                last := len(db.freeConn) - 1
                // Use slow delete as order is required to ensure
                // connections are reused least idle time first.
                copy(db.freeConn[i:], db.freeConn[i+1:])
                db.freeConn[last] = nil
                db.freeConn = db.freeConn[:last]
                i--
            } else if d2 := c.createdAt.Sub(expiredSince); d2 < d {
                // Prevent connections sitting the freeConn when they
                // have expired by updating our next deadline d.
                d = d2
            }
        }
        db.maxLifetimeClosed += int64(len(closing)) - idleClosing
    }




    return d, closing
}
```  
  
   
# 6 总结  
  
至此，全文结束.  
  
本期我们一起深入解析了 golang 标准库 database/sql 当中的源码：  
- • sql 库将与具体数据库交互的细节托管给抽象的数据库驱动接口，由具体的数据库类型实现具体的版本  
  
- • sql 库采用连接池的方式，进行数据库连接的复用管理. 针对于过期的连接启用了一个异步协程专门负责执行清理操作  
  
在此做个展望. 未来两期，我们一起展开探讨 mysql driver 库以及 orm 框架 gorm 库的底层实现原理.  
  
  
  
