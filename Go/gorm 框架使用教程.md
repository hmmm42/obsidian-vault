#  gorm 框架使用教程   
原创 小徐先生1212  小徐先生的编程世界   2023-10-20 19:06  
  
# 0 前言  
  
近期我们在分享有关于 golang-sql 系列专题，前两期分享内容前瞻：  
- • [Golang sql 标准库源码解析](http://mp.weixin.qq.com/s?__biz=MzkxMjQzMjA0OQ==&mid=2247484727&idx=1&sn=a05080a9494438c0fa57c92b9f159d55&chksm=c10c4be9f67bc2ff48b37fe80215f55f2338b700f55896ff2452dc183464c025695f2d272620&scene=21#wechat_redirect)  
  
  
- • [Golang mysql 驱动源码解析](http://mp.weixin.qq.com/s?__biz=MzkxMjQzMjA0OQ==&mid=2247484744&idx=1&sn=d315ce9c80a502a35677595638d450bb&chksm=c10c4b96f67bc2806947de5e528383bb81471f3b8be5b27796d6dc2f030d7bf5ed02145ae077&scene=21#wechat_redirect)  
  
  
从本期开始，我们正式步入 gorm 框架的领域.  
  
**gorm 是 golang 中最流行的 orm 框架，为 go 语言使用者提供了简便且丰富的数据库操作 api**.  
  
有关 gorm 的分享话题会分为实操篇和原理篇，本篇是其中的实操篇，旨在向大家详细介绍 gorm 框架的使用方法.  
  
gorm 本身也支持多种数据库类型，**在本文中，统一以 mysql 作为操作的数据库类型**.  
  
有关 gorm 的更多资讯：  
- • 开源地址：https://github.com/go-gorm/gorm  
  
- • 中文教程：https://gorm.io/zh_CN/docs/  
  
   
# 1 数据库  
## 1.1 数据库  
  
本章中，我们重点向大家介绍如何通过 gorm 创建 mysql db 实例以及完成 db 配置：  
- • 设置好连接 mysql 的 dsn（data source name）  
  
- • 通过 gorm.Config 完成 db 有关的自定义配置  
  
- • 通过 gorm.Open 方法完成 db 实例的创建  
  
对应流程示例如下：  
```
package mysql


import (
    "gorm.io/driver/mysql"
    "gorm.io/gorm"
)


var (
    // 全局 db 模式
    db *gorm.DB
    // 单例工具
    dbOnce sync.Once
    // 连接 mysql 的 dsn
    dsn = "username:password@(ip:port)/database?timeout=5000ms&readTimeout=5000ms&writeTimeout=5000ms&charset=utf8mb4&parseTime=true&loc=Local"
)


func getDB()(*gorm.DB ,error){
    var err error
    dbOnce.Do(func(){
       // 创建 db 实例
       db, err = gorm.Open(mysql.Open(dsn),&gorm.Config{})
    })  
    return db,err
}
```  
  
与 database/sql 中原生的 sql.DB 实例不同，在**创建 gorm.DB 实例时，默认情况下会向数据库服务端发起一次连接，以保证 dsn 的正确性**.  
  
另外想提的一个点是，在 gorm 体系之下，这个 DB 对象是绝对的核心，基本所有操作都是围绕着这个 DB 实例展开的，后续大家也会看到大量通过使用 DB 进行链式调用的代码风格，形如：  
```
    db.Where(...).Order(...).WithContext(...).Find(...)
```  
  
   
## 1.2 配置  
  
在创建 gorm.DB 实例时，可以通过 gorm.Config 进行自定义配置，其中各配置项含义如下：  
```
type Config struct {
    // gorm 中，针对单笔增、删、改操作默认会启用事务. 可以通过将该参数设置为 true，禁用此机制
    SkipDefaultTransaction bool
    // 表、列的命名策略
    NamingStrategy schema.Namer
    // 自定义日志模块
    Logger logger.Interface
    // 自定义获取当前时间的方法
    NowFunc func() time.Time
    // 是否启用 prepare sql 模板缓存模式
    PrepareStmt bool
    // 在 gorm 创建 db 实例时，会创建 conn 并通过 ping 方法确认 dsn 的正确性. 倘若设置此参数，则会禁用 db 初始化时的 ping 操作
    DisableAutomaticPing bool
    // 不启用迁移过程中的外联键限制
    DisableForeignKeyConstraintWhenMigrating bool
    // 是否禁用嵌套事务
    DisableNestedTransaction bool
    // 是否允许全局更新操作. 即未使用 where 条件的情况下，对整张表的字段进行更新
    AllowGlobalUpdate bool
    // 执行 sql 查询时使用全量字段
    QueryFields bool
    // 批量创建时，每个批次的数据量大小
    CreateBatchSize int
    // 条件创建器
    ClauseBuilders map[string]clause.ClauseBuilder
    // 数据库连接池
    ConnPool ConnPool
    // 数据库连接器
    Dialector
    // 插件集合
    Plugins map[string]Plugin
    // 回调钩子
    callbacks  *callbacks
    // 全局缓存数据，如 stmt、schema 等内容
    cacheStore *sync.Map
}
```  
  
   
# 2 模型  
## 2.1 gorm.Model  
  
在定义持久化模型 PO(persist object) 时，推荐组合使用 gorm.Model 中预定义的几个通用字段，包括主键、增删改时间等：  
```
type PO struct {
    gorm.Model
}
```  
  
   
```
package gorm
type Model struct {
    // 主键 id
    ID        uint `gorm:"primarykey"`
    // 创建时间
    CreatedAt time.Time
    // 更新时间
    UpdatedAt time.Time
    // 删除时间
    DeletedAt DeletedAt `gorm:"index"`
}
```  
  
值得一提的是，在 gorm 体系中，一个 po 模型只要启用了 deletedAt 字段，则默认会开启**软删除机制：在执行删除操作时，不会立刻物理删除数据，而是仅仅将 po 的 deletedAt 字段置为非空.**  
  
这里暂且点到为止，软删除的细节本文第 4 章中再作详细展开.  
  
   
## 2.2 标签  
  
下面我们介绍一下 po 模型中的常用标签：  
```
type PO struct{
   // 组合使用 gorm Model，引用 id、createdAt、updatedAt、deletedAt 等字段
   gorm.Model
  // 列名为 name；列类型字符串；使用该列作为唯一索引
   Name string `gorm:"column:name;type:varchar(15);unique_index"` 
   // 该列默认值为 18
   Age int `gorm:"default:18"` 
   // 该列值不为空
   Email string `gorm:"not null"` 
   // 该列的数值逐行递增
   Num int `gorm:"auto_increment"` 
}
```  
  
   
  
几类常用的标签及对应的用途展示如下表：  
  
<table><thead style="line-height: 1.75;background: rgba(0, 0, 0, 0.05);font-weight: bold;color: rgb(63, 63, 63);"><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;"><strong style="line-height: 1.75;color: rgb(15, 76, 129);">标签</strong></td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;"><strong style="line-height: 1.75;color: rgb(15, 76, 129);">作用</strong></td></tr></thead><tbody><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">primarykey</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">主键</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">unique_index</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">唯一键</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">index</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">键</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">auto_increment</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">自增列</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">column</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">列名</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">type</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">列类型</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">default</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">默认值</td></tr><tr><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">not null</td><td style="line-height: 1.75;border-color: rgb(223, 223, 223);padding: 0.25em 0.5em;color: rgb(63, 63, 63);">非空</td></tr></tbody></table>  
  
## 2.3 零值  
  
在使用 po 模型时，可能会存在一个与零值有关的问题.  
  
在 **golang 中一些基础类型都存在对应的零值，即便用户未显式给字段赋值，字段在初始化时也会首先赋上零值**. 比如 bool 类型的零值为 false；string 类型为 ""，int 类型为 0.  
  
这样就会导致，在我们执行创建、更新等操作时，倘若 po 模型中存在零值字段，此时 **gorm 无法区分到底是用户显式声明的零值，还是未显式声明而被编译器默认赋予的零值. 在无法区分的情况下，gorm 会统一按照后者，采取忽略处理的方式**.  
  
倘若此时我们想要明确是显式将字段设置为零值的，对应可以采取以下两种处理方式：  
  
- • **使用指针类型：**  
  
我们将 age 字段类型设定为 *int，只要指针非空，就代表使用方进行了显式赋值.  

```
type PO struct{
   gorm.Model
   Age *int `gorm:"column:age"` // 默认值为 18
}
```  
  
   
- • **使用 sql.Nullxx 类型：**  
  
我们将 age 字段类型设定为 sql.NullInt64，只要 Valid 标识为 true，就代表使用方进行了显式赋值.  
```
type PO struct{
   gorm.Model
   Age sql.NullInt64 `gorm:"column:age"` // 默认值为 18
}


type NullInt64 struct {
    Int64 int64
    Valid bool // Valid is true if Int64 is not NULL
}
```  
  
   
## 2.4 时间&表情  
  
在设置 dsn 时，建议添加上 parseTime=true 的设置，这样能兼容支持将 mysql 中的时间解析到 golang 中的 time.Time 类型字段  
  
![](https://mmbiz.qpic.cn/sz_mmbiz_png/3ic3aBqT2ibZvN8P96hsztXPCp6gOB5UD2cDjmQ5fz7xL0EnPKobH5fsjcXSOI4SIHOJgZ8Q5sOAP0TAbwWLBkog/640?wx_fmt=png "")  
  
   
  
在设定字符集时，建议使用 uft8mb4 替代 utf8，这样能支持更广泛的字符集，包括表情包等特殊字符的存储  
  
![](https://mmbiz.qpic.cn/sz_mmbiz_png/3ic3aBqT2ibZvN8P96hsztXPCp6gOB5UD2vKKP4tVbjfQL6WbproD3F6T7mmRoqfjxQsY8dTwngUy54ZqzOvWIXQ/640?wx_fmt=png "")  
  
   
## 2.5 表名指定  
  
在定义 PO 模型时，可以通过声明 TableName 方法来指定其对应的表名：  
```
func (p PO) TableName() string {
    return "po"
}
```  
  
   
  
此外，也可以在操作 gorm.DB 实例时通过 Table 方法显式指定表名：  
```
    db = db.Table("po")
```  
  
   
  
接下来我们按照 CRUD 的顺序，分别介绍 gorm 体系下的四种操作类型：  
# 3 创建  
## 3.1 单笔创建  
  
执行单笔记录创建操作：  
- • 创建 po 实例  
  
- • po 实例的 age 字段通过 \*int 方式规避零值问题  
  
- • po 模型已声明了 TableName 方法，用于关联数据表  
  
- • 链式操作 DB，Create 方法传入 po 指针，完成创建  
  
- • 通过 DB.Error 接收返回的错误  
  
- • 通过 DB.RowsAffected 获取影响的行数  
  
- • 由于传入的 po 为指针，创建完成后，po 实例会更新主键信息  
  
```
type PO struct{
   gorm.Model
   Age *int `gorm:"column:age"` // 默认值为 18
}


func Test_db_create(t *testing.T) {
    // ...
    // 构造 po 实例，通过指针方式，实现将 age 零值存入数据库(age 存在默认值为 18)
    age := 0
    po := PO{
        Age: &age,
    }
    
    // 执行创建操作
    // INSERT INTO `po` (`age`) VALUES (0);
    resDB := db.WithContext(ctx).Create(&po)
    if resDB.Error != nil {
        t.Error(resDB.Error)
        return
    }


    // 影响行数 -> 1
    t.Logf("rows affected: %d", resDB.RowsAffected)
    // 结果输出
    t.Logf("po: %+v", po)
}
```  
  
   
## 3.2 批量创建  
  
Create 方法同样支持完成 po 的批量创建操作，示例如下：  
```
func Test_db_batchCreate(t *testing.T) {
    // ...
    // 构造 po 列表 
    age1 := 20
    age2 := 21
    pos := []PO{
        {Age: &age1},
        {Age: &age2},
    }


    // 超时控制
    ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
    defer cancel()    
    
    // 批量创建
    // 批量创建时会根据 gorm.Config 中的 CreateBatchSize 进行分批创建操作
    resDB := db.WithContext(ctx).Table("po").Create(&pos)
    if resDB.Error != nil {
        t.Error(resDB.Error)
        return
    }


    // 输出影响行数 -> 2
    t.Logf("rows affected: %d", resDB.RowsAffected)


    // 打印各 po，输出其主键
    for _, po := range pos {
        t.Logf("po: %+v\n", po)
    }
}
```  
  
   
  
另一种批量创建的方式是使用 CreateInBatches 方法，可以通过在入参中显式指定单个批次创建的数据量上限：  
```
func Test_db_batchCreate(t *testing.T) {
    // ...
    // 构造 po
    age1 := 20
    // ...
    age1000 := 21
    pos := []PO{
        {Age: &age1},
        // ...
        {Age: &age1000},
    }
    
    // 超时控制
    ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
    defer cancel()


    // 批量创建，在 createInBatch 方法中显式指定了单个批次的数据上限 正好为 pos 切片的长度
    resDB := db.WithContext(ctx).Table("po").CreateInBatches(&pos, len(pos))
    if resDB.Error != nil {
        t.Error(resDB.Error)
        return
    }


    // 影响行数 -> len(p)
    t.Logf("rows affected: %d", resDB.RowsAffected)
    // 打印各 po，输出其主键
    for _, po := range pos {
        t.Logf("po: %+v\n", po)
    }
}
```  
  
   
## 3.3 upsert  
  
所谓 upsert，指的是数据如果不存在则创建，倘若存在，则按照预定义的策略执行更新操作.  
  
可以通过 DB 的 Clauses 方法完成 upsert 的策略设定：  
- • **策略 I：倘若冲突，则忽略**  
  
```
func Test_db_upsert(t *testing.T) {
    // ...
    pos := []PO{
        //...
    }
    
    // 批量插入，倘若发生冲突(id主键），则直接忽略执行该条记录
    // INSERT INTO `po` ... ON DUPLICATE KEY UPDATE `id` = `id`
    resDB := db.WithContext(ctx).Clauses(
        clause.OnConflict{
            Columns:   []clause.Column{{Name: "id"}},
            DoNothing: true,
        },
    ).Create(&pos)
}
```  
  
   
- • **策略 II：倘若冲突，则更新指定字段**  
  
```
func Test_db_upsert(t *testing.T) {
    // ...
    pos := []PO{
        //...
    }


    // 批量插入，倘若发生冲突(id主键），则将 age 更新为新值
    // INSERT INTO `po` ... ON DUPLICATE KEY UPDATE `age` = VALUES(age)
    resDB := db.WithContext(ctx).Clauses(
        clause.OnConflict{
            Columns:   []clause.Column{{Name: "id"}},
            DoUpdates: clause.AssignmentColumns([]string{"age"}),
        },
    ).Create(&pos)
}
```  
  
   
# 4 删除  
## 4.1 单条删除  
  
删除是一类比较敏感的操作，需要确保设置合适的限制条件，在没有指定 where 条件时，需要确保显式指定了 po 模型的主键：  
- • 创建 po 模型，设置主键值  
  
- • 执行 Delete 方法，传入 po 实例指针  
  
- • 由于 po 模型存在 deletedAt 字段，所以采取的是软删除操作  
  
```
func Test_db_delete(t *testing.T) {
    // ...
    // 构造 po
    po := PO{
        Model: gorm.Model{
            // 指定主键
            ID: 1,
        },
    }


    // 超时控制
    ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
    defer cancel()


    // 软删除
    // UPDATE `po` SET deleted_at = /* current unix second */ WHERE id = 1
    resDB := db.WithContext(ctx).Delete(&po)
    if resDB.Error != nil {
        t.Error(resDB.Error)
        return
    }


    // 影响行数 —> 1
    t.Logf("rows affected: %d", resDB.RowsAffected)
}
```  
  
   
## 4.2 批量删除  
  
通过设定 where 条件，可以执行批量删除操作，代码示例如下：  
```
func Test_db_delete(t *testing.T) {
    // ...
    // 构造 po，未显式指定 id
    po := PO{}


    // 超时控制
    ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
    defer cancel()


    // 批量软删除所有 age > 10 的记录
    // UPDATE `po` SET deleted_at = /* current unix second */ WHERE age > 10
    resDB := db.WithContext(ctx).Where("age > ?", 10).Delete(&po)
    if resDB.Error != nil {
        t.Error(resDB.Error)
        return
    }


    // 影响行数 —> x
    t.Logf("rows affected: %d", resDB.RowsAffected)
}
```  
  
   
## 4.3 软删除  
  
在 po 模型中，倘若使用 gorm.Model **启用了 DeletedAt 字段的话，会启用软删除机制**.  
```
type PO struct {
    gorm.Model
    Age *int `gorm:"column:age"` // 默认值为 18
}


type Model struct {
    ID        uint `gorm:"primarykey"`
    CreatedAt time.Time
    UpdatedAt time.Time
    // 删除键，启用软删除机制
    DeletedAt DeletedAt `gorm:"index"`
}
```  
  
   
  
在**软删除模式下，Delete 方法只会把 DeletedAt 字段置为非空**，设为删除时的时间戳.  
```
func Test_db_delete(t *testing.T) {
    // ...
    // 软删除
    // UPDATE `po` SET deleted_at = /* current unix second */ WHERE ...
    db.Delete(&po)
    // ...
}
```  
  
   
  
**后续在查询和更新操作时，默认都会带上【 WHERE deleted_at IS NULL】的条件，保证这部分软删除的数据是不可见的**.  
```
func Test_db_query(t *testing.T) {
    // ...
    // 正常查询无法获取到软删除的数据
    // SELECT * FROM `po` WHERE id = 1 AND deleted_at IS NULL 
    db.WHERE("id = ?",1).Find(&po)       
}
```  
  
   
  
倘若想要**获取到这部分软删除状态的数据，可以在查询时带上 Unscope 标识**：  
```
func Test_db_unscopeQuery(t *testing.T) {   
    // 允许查询到软删除的数据
    // SELECT * FROM `po` WHERE id = 1
    db.Unscope().WHERE("id = ?",1).Find(&po)
    // ...
}
```  
  
   
## 4.4 物理删除  
  
在 po 模型中**未启用 deletedAt 字段时，执行的 Delete 操作都是物理删除**.  
  
在启用 **deletedAt 字段时，可以通过带上 unscope 标识，来强制执行物理删除操作**：  
```
func Test_db_unscopeDelete(t *testing.T) {
    // ...
    // 硬删除
    // DELETE FROM `po` WHERE id = 1 
    db.Unscope().Delete(&po)
    // ...
}
```  
  
   
# 5 更新  
  
更新操作其实又分为增量更新（PATCH）和全量保存（PUT）的语义，前者对应的是 DB 的 Updates 方法，后者对应的是 DB 的 Save 方法.  
## 5.1 批量更新  
  
在 updates 时，只会在原数据记录的基础上，增量更新用户显式声明部分的字段：  
- • 在 po 模型中，通过指针的方式，标识字段 age 和 name 被显式赋予了零值  
  
- • 调用 updates 方法，更新 age 和 name 列  
  
- • 本次 updates 操作会失败，因为没有通过 where 限定条件，最终抛出 gorm.ErrMissingWhereClause 的错误  
  
```
func Test_db_update(t *testing.T) {
    // ...
    age := 0
    name := ""
    // 批量更新 po 中显式声明的字段，未显式指定 where 条件，会报错 gorm.ErrMissingWhereClause
    // UPDATE `po` SET age = 0, name = ""
    resDB := db.WithContext(ctx).Updates(&PO{
        Age:  &age,
        Name: &name,
    })
    if resDB.Error != nil {
        t.Error(resDB.Error)
        return
    }


    // 影响行数 —> x
    t.Logf("rows affected: %d", resDB.RowsAffected)
}
```  
  
   
  
在没有限定 where 条件的情况下，支持 updates 操作是非常危险的，这意味着会对整张表执行更新操作，因此默认情况下 gorm 会限制这种行为. 倘若用户希望这种操作能够得到允许，则可以采取如下两种方式：  
- • 方式 I：在 gorm.Config 中将 AllowGlobalUpdate 参数设为 true  
  
- • 方式 II：开启一个 session 会话，临时将 AllowGlobalUpdate 参数设为 true（**比较推荐，更能显式突出这次操作的特殊性**）  
  
方式 II 的示例代码如下：  
```
func Test_db_update(t *testing.T) {
    // ...
    // 开启一个会话，将全局更新配置设为 true
    dbSession := db.Session(&gorm.Session{
        AllowGlobalUpdate: true,
    })


    age := 0
    name := ""
    // 全局更新 age 和 name 字段
    // UPDATE `po` SET age = 0, name = ""
    resDB := dbSession.WithContext(ctx).Updates(&PO{
        Age:  &age,
        Name: &name,
    })
    if resDB.Error != nil {
        t.Error(resDB.Error)
        return
    }


    // 影响行数 —> x
    t.Logf("rows affected: %d", resDB.RowsAffected)
}
```  
  
   
  
常规的更新操作是通过 where 进行条件限制：  
```
func Test_db_update(t *testing.T) {
    // ...


    age := 0
    name := ""
    // 批量更新，po 中所有显式声明的字段
    // UPDATE `po` SET age = 0, name = "" WHERE age > 10
    resDB := db.WithContext(ctx).Where("age > ?", 10).Updates(&PO{
        Age:  &age,
        Name: &name,
    })
    if resDB.Error != nil {
        t.Error(resDB.Error)
        return
    }


    // 影响行数 —> x
    t.Logf("rows affected: %d", resDB.RowsAffected)
}
```  
  
   
  
更新时支持通过 Select 或者 Omit 语句，来选定或者忽略指定的列：  
```
    // 限定只更新 age 字段
    // UPDATE `po` SET age = 0 WHERE age > 10
    resDB := db.WithContext(ctx).Where("age > ?", 10).Select("age").Updates(&PO{
        Age:  &age,
        Name: &name,
    })
```  
  
   
```
    // 限定更新时忽略 age 字段
    // UPDATE `po` SET name = "" WHERE age > 10
    resDB := db.WithContext(ctx).Where("age > ?", 10).Omit("age").Updates(&PO{
        Age:  &age,
        Name: &name,
    })
```  
  
   
## 5.2 表达式更新  
  
更新时，还可以通过表达式执行 sql 更新操作，比如把年龄放大两倍再加一：  
```
func Test_db_update(t *testing.T) {
    // ...


    // UPDATE `po` SET age = age * 2 + 1 WHERE id = 1 
    resDB := db.WithContext(ctx).Table("po").Where("id = ?", 1).UpdateColumn("age", gorm.Expr("age * ? + ?", 2, 1))
    if resDB.Error != nil {
        t.Error(resDB.Error)
        return
    }


    // 影响行数 —> 1
    t.Logf("rows affected: %d", resDB.RowsAffected)
}
```  
  
   
## 5.3 json 列更新  
  
在 mysql 中有一种特殊的列类型——json. 针对 json 类型的列执行更新操作时，可以使用 gorm.io/datatypes lib 包中封装的相关方法：  
```
import(
    "gorm.io/datatypes"
)

func Test_db_updateJSON(t *testing.T) {
    // 对 extra json 字段新增一组 kv 对
    // UPDATE `po` SET extra = json_insert(extra,"$.key","value") WHERE id = 1
    resDB := db.Where("id = ?", 1).UpdateColumn("extra", datatypes.JSONSet("extra").Set("key", "value"))
    if resDB.Error != nil {
        t.Error(resDB.Error)
        return
    }
}
```  
  
   
## 5.4 批量保存  
  
DB 中的 Save 方法对应的是全量保存的语义，指的是会对整个 po 模型的数据进行溢写存储，即便其中有些未显式声明的字段，也会被更新为零值.  
  
基于此，Save 方法需要慎用，通常是先通过 query 方法查到数据并进行少量字段更新后，再调用 Save 方法进行保存，以保证 po 实例是拥有完整数据的：  
```
func Test_db_save(t *testing.T) {
    // ...
    // 首先查出对应的数据
    pos := []PO{
        {Model: gorm.Model{ID: 1}},
        {Model: gorm.Model{ID: 2}},
    }
    ctxDB := db.WithContext(ctx)
    if err := ctxDB.Scan(&pos).Error; err != nil {
        t.Error(err)
        return
    }


    // 更新数据
    for _, po := range pos {
        *po.Age += 100
    }


    // 将更新后的数据存储到数据库
    if err := ctxDB.Save(&pos); err != nil {
        t.Error(err)
        return
    }
}
```  
  
   
# 6 查询  
## 6.1 单笔查询  
  
gorm 中，First、Last、Take、Find 方法都可以用于查询单条记录. 前三个方法的特点是，倘若未查询到指定记录，则会报错 gorm.ErrRecordNotFound；最后一个方法的语义更软一些，即便没有查到指定记录，也不会返回错误.  
  
下面针对这四种方法逐一进行案例展示：  
- • First：  
  
返回满足条件的第一条数据记录，指的是主键最小的记录  
```
func Test_query(t *testing.T) {
    // ...
    // 查询到第一条记录返回. 由于 where 条件缺省，则会取主键最小的 记录
    var po PO
    // SELECT * FROM `po` WHERE deleted_at IS NULL ORDER BY id ASC LIMIT 1
    if err := db.WithContext(ctx).First(&po).Error; err != nil {
        t.Error(err)
        return
    }


    t.Logf("po: %+v", po)
}
```  
  
   
- • Last  
  
返回满足条件的最后一条数据记录，指的是主键最大的记录  
```
func Test_query(t *testing.T) {
    // ...


    // 取 age > 10 的记录中主键最大的记录
    var po PO
    // SELECT * FROM `po` WHERE age > 10 AND deleted_at IS NULL ORDER BY id DESC imit 1 
    if err := db.WithContext(ctx).Where("age > ?",10).Last(&po).Error; err != nil {
        t.Error(err)
        return
    }


    t.Logf("po: %+v", po)
}
```  
  
   
- • Take  
  
从满足条件的数据记录中随机返回一条：  
```
func Test_query(t *testing.T) {
    // ...


    // 取 id < 10 的记录中随机一条记录返回
    var po PO
    // SELECT * FROM `po` WHERE id < 10  AND deleted_at IS NULL LIMIT 1
    if err := db.WithContext(ctx).Where("id < ?",10).Take(&po).Error; err != nil {
        t.Error(err)
        return
    }


    t.Logf("po: %+v", po)
}
```  
  
   
- • Find  
  
从满足条件的数据记录中随机返回一条，即便没有找到记录，也不会抛出错误  
```
func Test_query(t *testing.T) {
    // ...
    // 通过 find 检索记录，找不到满足条件的记录时，也不会返回错误
    var po PO
    // SELECT * FROM `po` WHERE id = 999 AND deleted_at IS NULL 
    if err := db.WithContext(ctx).Where("id = ?",999).Find(&po).Error; err != nil {
        t.Error(err)
        return
    }


    // po 里的数据可能为空
    t.Logf("po: %+v", po)
}
```  
  
   
  
查询时可以通过 Select 方法声明只返回特定的列：  
```
func Test_query(t *testing.T) {
    // ...
    // 只返回 age 列的数据
    var po PO
    // SELECT age FROM `po` WHERE id = 999 AND deleted_at IS NULL ORDER BY id ASC limit 1
    if err := db.WithContext(ctx).Select("age").Where("id = ?",999).First(&po).Error; err != nil {
        t.Error(err)
        return
    }


    // po 里只有 age 字段有数据
    t.Logf("po: %+v", po)
}
```  
  
   
## 6.2 批量查询  
  
Find 方法还可以应用于批量查询：  
```
func Test_batchQuery(t *testing.T) {
    // ...
    var pos []PO
    // SELECT * FROM `po` WHERE age > 1 AND deleted_at IS NULL 
    if err := db.WithContext(ctx).Where("age > ?", 1).Find(&pos).Error; err != nil {
        t.Error(err)
        return
    }


    for _, po := range pos {
        t.Logf("po: %+v\n", po)
    }
}
```  
  
   
  
此外，还可以使用 Scan 方法执行批量查询，Scan 与 Find 的区别在于，使用时必须显式指定表名：  
```
func Test_batchQuery(t *testing.T) {
    // ...
    var pos []PO
    // SELECT * FROM `po` WHERE age > 1 AND deleted_at IS NULL  
    if err := db.WithContext(ctx).Table("po").Where("age > ?", 1).Scan(&pos).Error; err != nil {
        t.Error(err)
        return
    }


    for _, po := range pos {
        t.Logf("po: %+v\n", po)
    }
}    
```  
  
   
  
此外，还可以通过 Pluck 方法实现批量查询指定列的操作：  
```
func Test_query(t *testing.T) {
    // ...


    var ages []int64
    // SELECT age from `po` WHERE age > 1 AND deleted_at IS NULL 
    if err := db.WithContext(ctx).Table("po").Where("age > ?", 1).Pluck("age", &ages).Error; err != nil {
        t.Error(err)
        return
    }


    t.Logf("ages: %+v", ages)
}
```  
  
   
## 6.3 条件查询  
  
限定条件时，可以通过 Where 链式调用的方式实现 "AND" 的语义，也可以通过 Or 方法实现 "OR" 的语义：  
```
   // WHERE age = 1 AND name = 'xu'
   db.Where("age = 1").Where("name = ?",xu)
```  
  
   
```
   // WHERE age = 1 OR name = 'xu'
   db.Where("age = 1").Or("name = ?","xu") 
```  
  
   
  
嵌套的条件也是可以支持的：  
```
   // WHERE (age = 1 AND name = 'xu') OR (age = 2 AND name  = 'x')
   db.Where(db.Where("age = 1").Where("name = ?","xu")).Or(db.Where("age = 2").Where("name = ?","x"))
```  
  
   
  
在 where 条件中结合对 json 列的使用也是可以支持的：  
- • **案例I：json 列存在指定 kv 对**  
  
```
func Test_jsonQuery(t *testing.T) {
    // ...
  
    var pos []PO
    // SELECT * FROM `po` WHERE json_extract("extra","$.key") = "value" AND deleted_at IS NULL 
    if err := db.WithContext(ctx).Table("po").Where(datatypes.JSONQuery("extra").Equals("value", "key")).Find(&pos).Error; err != nil {
        t.Error(err)
        return
    }


    for _, po := range pos {
        t.Logf("po: %+v\n", po)
    }
}
```  
  
   
- • **案例II：json 列存在指定 key**  
  
```
func Test_jsonQuery(t *testing.T) {
    // ...


    var pos []PO
    // SELECT * FROM `po` WHERE json_extract("extra","$.key") IS NOT NULL AND deleted_at IS NULL 
    if err := db.WithContext(ctx).Table("po").Where(datatypes.JSONQuery("extra").HasKey("key")).Find(&pos).Error; err != nil {
        t.Error(err)
        return
    }


    for _, po := range pos {
        t.Logf("po: %+v\n", po)
    }
}
```  
  
   
## 6.4 数量统计  
  
可以通过 DB.Count 方法实现数量统计操作：  
```
func Test_Count(t *testing.T) {
    // ...


    var cnt int64
    // SELECT COUNT(*) FROM `po` WHERE age > 10 AND deleted_at IS NULL
    if err := db.WithContext(ctx).Table("po").Where("age > ?", 10).Count(&cnt); err != nil {
        t.Error(err)
        return
    }
    
    t.Logf("cnt: %d", cnt)
}
```  
  
   
## 6.5 分组求和  
  
对应于 group 分组操作可以通过 DB.Group 方法实现，分组之后的 Sum、Max、Avg 等聚合函数都可以通过 Select 方法进行声明. 此处给出对应于 Sum 函数的使用示例：  
```
type UserRecord struct {
    UserID int64 `gorm:"int64"`
    Amount int64 `gorm:"amount"`
}


func Test_sumGroup(t *testing.T) {
    // ...
    var groups []UserRecord
    // SELECT user_id, sum(amount) AS amount FROM `user_record` WHERE id < 100 AND deleted_at IS NULL GROUP BY user_id
    resDB := db.WithContext(ctx).Table("user_record").Select("user_id", "sum(amount) AS amount").
        Where("id < ?", 100).Group("user_id").Scan(&groups)
    if resDB.Error != nil {
        t.Error(resDB.Error)
        return
    }


    for _, group := range groups {
        t.Logf("group: %+v\n", group)
    }
}
```  
  
   
## 6.6 子查询  
  
对应于子查询操作的使用示例：  
```
func Test_subQuery(t *testing.T) {
    db, _ := getDB()
    ctx := context.Background()


    // UPDATE `user_record` SET amount = (SELECT amount FROM `user_record` WHERE user_id = 1000 ORDER BY id DESC limit 1) WHERE user_id = 100 
    subQuery := db.Table("user_record").Select("amount").Where("user_id = ?", 1000)
    
    resDB := db.WithContext(ctx).Table("user_record").Where("user_id = ?", 100).UpdateColumn("amount", subQuery)
    if resDB.Error != nil {
        t.Error(resDB.Error)
        return
    }
}
```  
  
   
## 6.7 排序偏移  
  
在批量查询的场景中，通常还会存在排序和偏移的需求：  
```
func Test_orderLimit(t *testing.T) {
    db, _ := getDB()
    ctx := context.Background()


    var pos []PO
    // SELECT * FROM `po` WHERE id > 10 AND deleted_at is NULL ORDER BY age DESC LIMIT 2 OFFSET 10
    if err := db.WithContext(ctx).Table("po").Where("id > ?", 10).Order("age DESC").Limit(2).Offset(10).Scan(&pos).Error; err != nil {
        t.Error(err)
        return
    }


    for _, po := range pos {
        t.Logf("po: %+v\n", po)
    }
}
```  
  
   
# 7 事务  
  
本章介绍一下如何基于 gorm DB 实现事务和写锁操作：  
## 7.1 事务  
  
使用事务的流程：  
- • 调用 db.Transaction 方法开启事务  
  
- • 在 Transaction 中可以通过闭包函数执行事务逻辑，其中所有事务操作都需要围绕着 tx *gorm.DB 实例展开  
  
- • 在闭包函数中，一旦返回 error 或者发生 panic，gorm 会自动执行回滚操作；倘若返回的 error 为 nil，gorm 会自动执行提交操作  
  
- • 使用方也可以根据自己的需要，调用 tx.Rollback 和 tx.Commit 方法提前执行回滚或提交操作  
  
```
func Test_tx(t *testing.T) {
    // 超时控制
    ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
    defer cancel()
  
    // 需要包含在事务中执行的闭包函数
    do := func(tx *gorm.DB) error {
        // do something ...
        return nil
    }


    // 开启事务
    // BEGIN
    // OPERATE...
    // COMMIT/ROLLBACK
    if err := db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
        // do some preprocess ...
        // do ...
        err := do()
        // do some postprocess ...
        return err
    }); err != nil {
        t.Error(err)
    }
}
```  
  
   
## 7.2 写锁  
  
在事务中，针对某条记录可以通过 select for update 的方式进行加持写锁的操作：  
```
func Test_tx(t *testing.T) {
    // 超时控制
    ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
    defer cancel()
  
    // 需要包含在事务中执行的闭包函数
    do := func(ctx context.Context, tx *gorm.DB, po *PO) error {
        // do something ...
        return nil
    }


    // BEGIN 
    // SELECT * FROM po WHERE id = 1 AND deleted_at IS NULL ORDER BY id ASC limit 1 FOR UPDATE
    // OPERATE ....
    // COMMIT/ROLLBACK
    // 开启事务
    db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
        // 针对一条 po 记录加写锁
        var po PO
        if err := tx.Set("gorm: query option", "FOR UPDATE").Where("id = ?", 1).First(&po).Error; err != nil {
            return err
        }
        
        // 执行业务逻辑
        return do(ctx, tx, &po)
    })
}
```  
  
   
# 8 回调  
  
在定义 po 模型时，可以遵循 gorm 中预留的接口协议，声明指定的回调方法，这样能在特定操作执行前后执行用户预期的回调逻辑：  
  
在 gorm 中预定义好的各个回调接口协议如下：  
```
// 创建操作前回调
type BeforeCreateInterface interface {
    BeforeCreate(*gorm.DB) error
}


// 创建操作后回调
type AfterCreateInterface interface {
    AfterCreate(*gorm.DB) error
}


// 更新操作前回调
type BeforeUpdateInterface interface {
    BeforeUpdate(*gorm.DB) error
}


// 更新操作后回调
type AfterUpdateInterface interface {
    AfterUpdate(*gorm.DB) error
}


// 保存操作前回调
type BeforeSaveInterface interface {
    BeforeSave(*gorm.DB) error
}


// 保存操作后回调
type AfterSaveInterface interface {
    AfterSave(*gorm.DB) error
}


// 删除操作前回调
type BeforeDeleteInterface interface {
    BeforeDelete(*gorm.DB) error
}


// 删除操作后回调
type AfterDeleteInterface interface {
    AfterDelete(*gorm.DB) error
}


// find 操作后回调
type AfterFindInterface interface {
    AfterFind(*gorm.DB) error
}
```  
  
   
# 9 总结  
  
本期和大家一起分享了 go 语言最常用 orm 框架——gorm 的使用教程，下期我们将和大家一起深入到 gorm 框架的源码，解析其底层的技术实现原理.  
  
  
  
