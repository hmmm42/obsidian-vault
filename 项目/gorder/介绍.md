# 项目总览
## 技术栈

gin, grpc, rabbitMQ, redis, mysql, stripe

## 项目亮点

- 基于 DDD 架构, 采用 CQRS 设计模式开发读写分离, 基于依赖倒置原则优化模块间交互, 提高了代码的可扩展性和可维护性.
- 使用 Consul 进行服务注册与发现, 使用 OpenTelemetry 和 Jaeger 进行分布式链路追踪, 实现快速故障排查和性能瓶颈定位.
- 接入 Stripe Api 实现在线支付功能.
- 使用 gRPC 进行各服务间通信, 使用 RabbitMQ 进行支付事件的创建和消费, 实现了支付流程的异步处理.
- 使用 Redis 实现分布式锁, 确保每个订单请求只处理一次.
==问题: redis 锁其实没起到作用, 修改为对商品的粒度==

# 项目架构
```
.
├── api
│   ├── openapi
│   ├── orderpb
│   └── stockpb
├── internal
│   ├── common
│   │   ├── broker
│   │   ├── client
│   │   │   └── order
│   │   ├── config
│   │   ├── decorator
│   │   ├── discovery
│   │   │   └── consul
│   │   ├── genproto
│   │   │   ├── orderpb
│   │   │   └── stockpb
│   │   ├── logging
│   │   ├── metrics
│   │   ├── middleware
│   │   ├── server
│   │   └── tracing
│   ├── kitchen
│   ├── order
│   │   ├── adapters
│   │   │   └── grpc
│   │   ├── app
│   │   │   ├── command
│   │   │   └── query
│   │   ├── convertor
│   │   ├── domain
│   │   │   └── order
│   │   ├── entity
│   │   ├── infrastructure
│   │   │   └── consumer
│   │   ├── ports
│   │   ├── service
│   │   └── tmp
│   ├── payment
│   │   ├── adapters
│   │   ├── app
│   │   │   └── command
│   │   ├── domain
│   │   ├── infrastructure
│   │   │   ├── consumer
│   │   │   └── processor
│   │   ├── service
│   │   └── tmp
│   └── stock
│       ├── adapters
│       ├── app
│       │   └── query
│       ├── domain
│       │   └── stock
│       ├── ports
│       ├── service
│       └── tmp
├── public
├── scripts
└── tmp
```

# 具体流程

## 流程图

![[Drawing 2025-03-05 19.47.00.excalidraw]]

## 1. 创建 Order

用户从浏览器挑选商品下单, 通过 http 接口对 OrderService 进行请求, 初始化订单 (此时订单状态为不确定), 期间前端对订单状态进行**轮询**, 直到支付成功.

## 2. 生成 Order

Order端 从 Stock端 检查库存, 成功后, 异步向 RabbitMQ 发送 OrderCreated 事件, Payment 端消费订单事件后, 调用 OrderService.Update, 订单状态更新为等待支付. 

## 3. 订单处理

Payment 端调用 Stripe API, 生成支付链接, 重定向到 Stripe 支付界面, 用户支付后, Stripe 通过 webhook 回调支付状态, Payment 端向 RabbitMQ 广播支付成功事件.

## 4. 订单完成

Order 端消费事件, 更新订单状态为支付成功. Kitchen 端同时也消费该事件. 出餐后, Kitchen 端调用 Order 接口, 更新订单状态为已完成.

# 实现细节
## 设计哲学
### DDD 架构
Domain Driven Design: 领域驱动设计, 通过领域模型来解决问题, 以领域模型为核心, 通过领域模型来驱动整个软件开发过程.
![image.png](https://raw.githubusercontent.com/hmmm42/Picbed/main/obsidian/pictures20250306125915210.png)
#### Domain
领域层, 包含领域模型和领域服务, 用于描述**业务逻辑**.
尽量依赖**接口**, 而不是具体实现.
需要与数据库解耦; 不需要感知任何具体的技术实现.
eg. order domain 中只有
### CQRS
Command Query Responsibility Segregation: 命令查询职责分离, 将读写操作分开, 通过 CommandHandler 和 QueryHandler 分别处理.  
*虽然 CQRS 模式中 command 不应该有返回值, 但其实也没有什么大问题, 主要是这里创建订单后需要 OrderID, 方便业务逻辑*
### 装饰器模式
在不改变原有对象的基础上, 动态地给一个对象添加一些额外的职责. 核心是接口, 通过装饰器逐层包装, 实现了链式调用.  
本项目采用 CQRS 设计模式, 给所有的 CommandHandler 和 QueryHandler 添加了 logger 和 metrics 装饰器, 分别用于记录日志和监控性能.

下面以 Command.create_order 为例子分析整个装饰器模式执行的流程:
```go
type CommandHandler[C, R any] interface {
	Handle(ctx context.Context, cmd C) (R, error)
}
```
CommandHandler 是一个接口, 接收2个泛型参数: C 和 R, 分别代表 Command 和 Result. 

```go
func ApplyCommandDecorators[C, R any]
(handler CommandHandler[C, R], logger *logrus.Entry, metricsClient MetricsClient)
CommandHandler[C, R] {
	return commandLoggingDecorator[C, R]{
		logger: logger,
		base: commandMetricsDecorator[C, R]{
			base:   handler,
			client: metricsClient,
		},
	}
}
```
每个对 CommandHandler 的实现在返回时都要包装 logger 和metrics 装饰器. ApplyCommandDecorators 返回的是一个接口, 并未对里面的逻辑有任何改动, 只是附加功能. 
调用链: logger -> metrics -> baseHandler

```go
type CreateOrder struct {
	CustomerID string
	Items      []*entity.ItemWithQuantity
}

type CreateOrderResult struct {
	OrderID string
}

type CreateOrderHandler decorator.CommandHandler[CreateOrder, *CreateOrderResult]
```
注意这里的首字母大小写区分:
CreateOrderHandler 是 CommandHandler 接口代入具体类型后的结果, 当然本身也是 CommandHandler. C, R 分别是 CreateOrder 和 CreateOrderResult.

createOrderHandler 是含有具体事务逻辑的结构, 拥有 Handle 方法, 自然实现了 CommandHandler 接口.
```go
func (c createOrderHandler) Handle(ctx context.Context, cmd CreateOrder) (*CreateOrderResult, error) {
	// 业务逻辑
}
```
返回 CreateOrderHandler 用了 ApplyCommandDecorators 包装.
```go
func NewCreateOrderHandler(
	orderRepo domain.Repository,
	stockGRPC query.StockService,
	channel *amqp.Channel,
	logger *logrus.Entry,
	metricClient decorator.MetricsClient,
) CreateOrderHandler {
	return decorator.ApplyCommandDecorators[CreateOrder, *CreateOrderResult](
		createOrderHandler{
			orderRepo: orderRepo,
			stockGRPC: stockGRPC,
			channel:   channel,
		},
		logger,
		metricClient,
	)
}
```
外界在 service/application.go 调用 NewCreateOrderHandler, 传入依赖.
### 依赖倒置原则
依赖注入

## 服务之间是如何连接的

## 充血模型
贫血模型: 对象仅承载数据属性, 业务逻辑分散在服务层(如 `Service` 或 `Handler`), 领域对象本身不包含行为.
充血模型: 对象同时承载数据属性和业务逻辑, 领域对象本身包含行为.
即数据结构和方法封装在一起, 通过方法来操作数据, 保证数据的一致性.
eg. 
```go
func NewOrder(id, customerID, status, paymentLink string, items []*entity.Item) (*Order, error) {
	if id == "" {
		return nil, errors.New("empty id")
	}
	if customerID == "" {
		return nil, errors.New("empty customerID")
	}
	if status == "" {
		return nil, errors.New("empty status")
	}
	if items == nil {
		return nil, errors.New("empty items")
	}
	return &Order{
		ID:          id,
		CustomerID:  customerID,
		Status:      status,
		PaymentLink: paymentLink,
		Items:       items,
	}, nil
}

```

## api
```
.
├── README.md
├── openapi
│   └── order.yml
├── orderpb
│   └── order.proto
└── stockpb
    └── stock.proto
```
api 部分存放接口相关协议, 用到了 openapi 和 grpc 两种协议.
### openapi
通过 YAML 定义API的细节，包括路径（如`/customer/{customerID}/orders`）、HTTP方法（如GET/POST）、参数（路径参数、请求体等）、响应模型（如`Order`和`Error`）等.

在这里定义了 Order, Item, ItemWithQuantity, Error 4种模型, 以及创建订单和获取订单的两个接口. 

http 协议, 通过 JSON 传输数据.
*所有数据结构都要在防腐层中进行相应转化*

### proto
通过 protobuf 定义接口的数据结构和方法, 用于 grpc 通信.

#### order.proto
- OrderService: 服务接口, 内有 CreateOrder, GetOrder, UpdateOrder 三个方法
- 数据结构: CreateOrderRequest, GetOrderRequest, Order, Item, ItemWithQuantity *数据结构只用于gRPC通信,其他地方需要转化后在使用*

#### stock.proto
- StockService: GetItems, CheckIfItemInStock 
- 数据结构: GetItemsRequest, GetItemsResponse, CheckIfItemInStockRequest, CheckIfItemInStockResponse

## internal
所有业务逻辑代码
**虽然本项目中 order/stock/payment/kitchen 都在一个文件夹内, 但实际中应该是分布式存储的, 通用的代码只能存放在 common 中, 其他的位置无法调用(即微服务架构)**
### common
存放通用代码
#### config
配置文件, 配合 viper 进行读取
#### server
服务端, 提供通用的运行 http/grpc 服务的方法.
##### http.go
```go
func RunHTTPServer(serviceName string, wrapper func(router *gin.Engine))
```
将传进来的 gin.Engine 包装 group, 分配中间件.
##### grpc.go
```go
func RunGRPCServer(serviceName string, registerServer func(server *grpc.Server))
```
#### client
客户端
##### order
openapi 自动生成的 CreateOrderRequest, 唯一作用是从用户发来的 gin.Context 中提取数据, 接着用于下一步处理.
##### grpc.go
```go
func NewStockGRPCClient(ctx context.Context) 
(client stockpb.StockServiceClient, close func() error, err error)

func NewOrderGRPCClient(ctx context.Context) 
(client orderpb.OrderServiceClient, close func() error, err error)
```
用来获取 grpcClient, 接受内部服务发送的 grpc 请求, 服务的注册与发现用到下面的 consul.

#### handler

##### errors
在接口层 / service 层包装错误

#### discovery
使用 consul 进行服务注册与发现
##### discovery.go
```go
type Registry interface {
	Register(ctx context.Context, instanceID, serviceName, hostPort string) error
	Deregister(ctx context.Context, instanceID, serviceName string) error
	Discover(ctx context.Context, serviceName string) ([]string, error)
	HealthCheck(instanceID string, serviceName string) error
}
```
服务注册与发现接口.
##### consul.go
实现了 Registry 接口, 用于服务注册与发现

##### grpc.go
```go
func RegisterToConsul(ctx context.Context, serviceName string) (func() error, error) 
func GetServiceAddr(ctx context.Context, serviceName string) (string, error)
```
RegisterToConsul 用于注册, 返回关闭函数和错误. 逻辑上, 会开启一个协程来重复获取 HealthCheck 的结果, 保证服务的可用性.
GetServiceAddr 顾名思义.
#### genproto
自动生成的 grpc 代码.
#### decorator
装饰器模式的具体实现, logger 和 metrics 装饰器, 分别用于记录日志和监控性能.
- logger: 使用 logrus 包记录日志
- metrics: 使用 prometheus 包监控性能

#### convertor
防腐层, 防止 proto 生成的数据结构泄露到业务逻辑中.
用 entity 作中间转化.
区分: entity 可以出现在任何地方, 但 domain 不能.
#### logging
配置 logrus 的初始化, 根据是否为本地环境来决定格式化输出.
##### 全链路可观测日志
提供两种方式:
- hook, 无需在每处都 logrus.WithContext
- logging 内封装 Infof/Errorf..., 自动调用logrus.WithContext
#### metrics
#### middleware
中间件
##### StructuredLog
##### RequestLog
#### broker
消息队列
##### Why rabbitMQ?
vs kfaka: 都基于 amqp, kfaka 性能高, 可用性高(分布式), 时效性不好(排队速度), 路由简单; rabbitMQ 路由丰富, 性能够用.
vs rocketMQ: 融合rabbitMQ和kfaka.
业务背景: 时效性, 一致性
##### event.go
消息队列要用到的2个事件:
```go
const (
	EventOrderCreated = "order.created"
	EventOrderPaid    = "order.paid"
)
```
##### rabbitmq.go
```go
func Connect(user, password, host, port string) (*amqp.Channel, func() error)
```
Connect 用于连接 RabbitMQ, 声明 EventOrderCreated 和 EventOrderPaid. 
EventOrderCreated 为 direct, 在create_order.go 和 payment/consumer.go 中进行同名队列绑定, 实现从 Order 端到 Payment 端的消息传递.
EventOrderPaid 为 fanout, 发布时同时广播到 order 和 kitchen.
全流程:
1. 支付成功后，Stripe webhook 触发
2. Payment 服务发布订单已支付消息到 order.paid Exchange
3. Order 服务的消费者从绑定的队列接收消息
4. Order 服务更新订单状态为已支付

```go
type RabbitMQHeaderCarrier map[string]interface{}
```
实现了 TextMapCarrier 接口, 用于 OpenTelemetry 的消息头, 实现异步链路追踪.
###### 死信队列
保存未被消费的消息, 用于后续重试.
#### tracing
分布式链路追踪
trace, span 区别: trace 跟随着 context, span 更细粒度, 不同函数调用就是不同 span.

## order
### adapters
#### mongoDB
Why mongoDB?
轻量级, 没有 column, 项目初期阶段方便写, 无需定义表结构.
## stock
### 扣减竞争bug
两个用户同时购买同一件商品, 最后扣除的库存数量是两者之一.
解决方案:
1. 悲观锁: SELECT ... FOR UPDATE, 一致性好, 性能慢
2. 乐观锁: 通过版本号判断是否被修改, 适用于高并发场景
## payment

## kitchen
不需要建立任何的 http/grpc 服务, 从 rabbitMQ 中消费消息.
本模块简单, 为简化架构不使用 CQRS, consumer.go 直接调用 orderGPRC.UpdateOrder.
#### check if items in stock
需要获取 priceID, 两种逻辑:
1. 从 stripe 获取: 实时性好, 链路更长 ==限制qps==
2. 从 redis 获取: 可能不一致

## 方便开发的工具
### Go

- viper: 读取环境配置文件
- air: 热加载代码
- go-cleanarch：检查项目是否符合预设的代码分层架构(如防止循环依赖)
- golangci-lint: 对所有模块进行深度检查, 包括语法错误, 潜在漏洞和代码风格问题. 通过配置文件 `.golangci.yaml` 自定义启用的检查规则.
- goimports: 自动格式化代码, 并自动导入依赖.

### Scripts
一些脚本
- genprotp/genopenapi: 用于 make 快速生成 openapi 和 grpc 代码, 保持 makefile 简洁
- lint.sh: 检查代码风格, 自动修正

### Web
- Apifox: 便捷生成 http 请求

### Docker
部署运行: consul, jaeger, rabbitMQ, mongoDB, mysql