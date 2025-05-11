# 定义服务接口(.proto)
```go
syntax = "proto3";
package orderpb;

option go_package = "github.com/hmmm42/gorder-v2/common/genproto/orderpb";
// option go_package = "./;proto"; // 生成的代码放在当前目录下的 proto 包中

import "google/protobuf/empty.proto";
service OrderService {
  rpc CreateOrder(CreateOrderRequest) returns (google.protobuf.Empty);
	// Empty 表示返回为空
  rpc GetOrder(GetOrderRequest) returns (Order);
  rpc UpdateOrder(Order) returns (google.protobuf.Empty);
}

message CreateOrderRequest {
  string CustomerID = 1;
  repeated ItemWithQuantity items = 2;
}

message GetOrderRequest {
  string OrderID = 1;
  string CustomerID = 2;
}

message ItemWithQuantity {
  string ID = 1;
  int32 Quantity = 2;
}

message Item {
  string ID = 1;
  string Name = 2;
  int32 Quantity = 3;
  string PriceID = 4;
}

message Order {
  string ID = 1;
  string CustomerID = 2;
  string Status = 3;
  repeated Item Items = 4;
  string PaymentLink = 5;
}
```
定义的`service`和`message`最后会生成相应的go代码

# 生成 Go 代码
```sh
protoc --go_out=./proto --go_opt=paths=source_relative \
       --go-grpc_out=./proto --go-grpc_opt=paths=source_relative \
       proto/greet.proto
```
`paths=source_relative` 是一个选项，表示生成的 Go 文件应该放在与 `.proto` 文件相同的**相对位置**。
go_out 和 go-grpc_out 的区别:
- go_out: 所有的`message`
- go-grpc_out: 所有的`service`, 每个都有相应的`client`和`server`结构

```sh
run protoc \
	-I="/usr/local/include/" \
	-I="${API_ROOT}" \
	"--go_out=${go_out}" --go_opt=paths=source_relative \
	--go-grpc_opt=require_unimplemented_servers=false \
	"--go-grpc_out=${go_out}" --go-grpc_opt=paths=source_relative \
	"${API_ROOT}/${dir}/$pb_file"

```
`/usr/local/include/` 通常包含一些标准的 Google Protobuf 文件（例如 `google/protobuf/empty.proto` 等）

## pb.UnimplementedGroupCacheServer
保证向前兼容性
```go
// greet_grpc.pb.go (在 require_unimplemented_servers=true 模式下生成的概念性接口)
type GreeterServer interface {
    SayHello(context.Context, *GreetRequest) (*GreetResponse, error)
    // 如果 .proto 更新了: SayGoodbye(context.Context, *GoodbyeRequest) (*GoodbyeResponse, error)

    // 这个方法名是 protoc 生成的，用于强制嵌入 UnimplementedGreeterServer
    // 只有 UnimplementedGreeterServer 结构体实现了这个方法
    mustEmbedUnimplementedGreeterServer()
}

// greet_grpc.pb.go (生成的 UnimplementedGreeterServer 结构体)
type UnimplementedGreeterServer struct {
    // ... （这里包含 SayHello, SayGoodbye 等方法的默认实现，都返回 Unimplemented 错误）
}

// UnimplementedGreeterServer 实现了 GreeterServer 接口中的强制嵌入方法
func (UnimplementedGreeterServer) mustEmbedUnimplementedGreeterServer() {}
```

**新代码 (.proto 更新, 增加了 SayGoodbye):** `GreeterServer` 接口现在需要 `SayHello`、`SayGoodbye` 和 `mustEmbedUnimplementedGreeterServer`。你的 `server` 结构体：

- 显式实现了 `SayHello`。
- 通过嵌入 `UnimplementedGreeterServer`，它**隐式地获得了** `SayGoodbye` 的*默认实现*和 `mustEmbedUnimplementedGreeterServer` 的实现。
- 所以，你的 `server` 结构体**仍然实现了更新后的** `GreeterServer` 接口的所有方法。**编译通过。**
- 运行时，如果调用 `SayHello`，会执行你显式实现的版本；如果调用 `SayGoodbye`，会执行嵌入的 `UnimplementedGreeterServer` 中的默认实现，返回 `Unimplemented` 错误。

如果明确显式实现所有接口, 编译时加上
`--go-grpc_opt=require_unimplemented_servers=false`, 这样生成的`service`接口不会包含`mustEmbedUnimplementedGreeterServer`方法。

# gRPC 服务端
简单例子
```go
type server struct {
	pb.UnimplementedGreeterServer // 嵌入 UnimplementedGreeterServer 以确保向前兼容性
}

// SayHello 实现了 GreeterServer 接口的 SayHello 方法
func (s *server) SayHello(ctx context.Context, in *pb.GreetRequest) (*pb.GreetResponse, error) {
	log.Printf("Received: %v", in.GetName()) // 从请求中获取 name 字段
	// 构建响应消息
	return &pb.GreetResponse{Message: "Hello " + in.GetName()}, nil
}

func main() {
	// 监听 TCP 端口
	port := ":50051" // gRPC 服务的典型端口
	lis, err := net.Listen("tcp", port)
	if err != nil {
		log.Fatalf("failed to listen: %v", err)
	}
	fmt.Printf("Server listening on port %s\n", port)
	
	// 创建一个新的 gRPC 服务器实例
	s := grpc.NewServer()
	
	// 在 gRPC 服务器上注册 Greeter 服务
	// RegisterGreeterServer 是由 protoc 生成的函数
	pb.RegisterGreeterServer(s, &server{}) // 将我们的 server 结构体注册为 Greeter 服务处理者
	
	// 开始服务
	// Serve() 是一个阻塞调用，直到 Stop() 或 GracefulStop() 被调用
	if err := s.Serve(lis); err != nil {
		log.Fatalf("failed to serve: %v", err)
	}
}

```
`pb.RegisterGreeterServer(s, &server{})`：将我们实现的 `server` 结构体注册到 gRPC 服务器上，告诉服务器当接收到 `Greeter` 服务的请求时，应该由这个 `server` 实例来处理。
## gorder 实例
**项目通用运行grpc服务端代码**
```go
func RunGRPCServerOnAddr(addr string, registerServer func(server *grpc.Server)) {
	logrusEntry := logrus.NewEntry(logrus.StandardLogger())
	grpcServer := grpc.NewServer(
		grpc.StatsHandler(otelgrpc.NewServerHandler()),
		// 中间件
		grpc.ChainUnaryInterceptor(
			grpc_tags.UnaryServerInterceptor(grpc_tags.WithFieldExtractor(grpc_tags.CodeGenRequestFieldExtractor)),
			grpc_logrus.UnaryServerInterceptor(logrusEntry),
			logging.GRPCUnaryInterceptor,
		),
		grpc.ChainStreamInterceptor(
			grpc_tags.StreamServerInterceptor(grpc_tags.WithFieldExtractor(grpc_tags.CodeGenRequestFieldExtractor)),
			grpc_logrus.StreamServerInterceptor(logrusEntry),
		),
	)
	registerServer(grpcServer)

	listen, err := net.Listen("tcp", addr)
	if err != nil {
		logrus.Panic(err)
	}
	logrus.Infof("Starting gRPC server, Listening: %s", addr)
	if err := grpcServer.Serve(listen); err != nil {
		logrus.Panic(err)
	}
}
```
**order grpc server**
app 使用依赖注入模式, 内部为CQRS设计
==app可以说就是整个服务, 所有功能的中转结合==
```go
type GRPCServer struct {
	app app.Application
}

func NewGRPCServer(app app.Application) *GRPCServer {
	return &GRPCServer{app: app}
}
...
// 具体实现 CreateOrder, GetOrder, UpdateOrder 方法
```

**main**
启动server, 需要提供`RegisterXXServer`
```go
application, cleanup := service.NewApplication(ctx)  
defer cleanup()

go server.RunGRPCServer(serviceName, func(server *grpc.Server) {
	svc := ports.NewGRPCServer(application)
	orderpb.RegisterOrderServiceServer(server, svc)
})

```

# gRPC 客户端
```go
func main() {
	// 为整个连接过程设置一个带有超时机制的上下文 (用于 NewClient)
	// 连接操作不应该无限期阻塞
	dialCtx, dialCancel := context.WithTimeout(context.Background(), 5*time.Second) // 例如，设置5秒拨号超时
	defer dialCancel() // 确保拨号上下文在函数退出时取消
	
	// 建立与 gRPC 服务器的连接，使用 grpc.NewClient
	// 将拨号上下文通过 grpc.WithContext 选项传递
	conn, err := grpc.NewClient(
		address, // 服务端地址作为第一个参数
		grpc.WithTransportCredentials(insecure.NewCredentials()), // 不安全凭证
		grpc.WithBlock(), // 阻塞直到连接成功或超时
		grpc.WithContext(dialCtx), // 将拨号上下文作为选项传递
	)
	if err != nil {
		log.Fatalf("did not connect: %v", err)
	}
	defer conn.Close() // 确保连接在 main 函数退出时关闭
	
	// 创建 Greeter 服务的客户端 Stub
	// NewGreeterClient 是由 protoc 生成的函数
	c := pb.NewGreeterClient(conn)
	
	// 为 RPC 调用设置一个带有超时机制的上下文
	// RPC 调用也不应该无限期阻塞
	rpcCtx, rpcCancel := context.WithTimeout(context.Background(), time.Second) // 例如，设置1秒RPC超时
	defer rpcCancel() // 确保 RPC 上下文在函数退出时取消
	
	// 调用 SayHello RPC 方法
	name := defaultName

	// 将用于 RPC 调用的上下文传递进去
	r, err := c.SayHello(rpcCtx, &pb.GreetRequest{Name: name})
	if err != nil {
		log.Fatalf("could not greet: %v", err)
	}
	
	// 打印响应消息
	log.Printf("Greeting: %s", r.GetMessage())
}
```

## gorder 实例
**通用client代码**
```go
func NewOrderGRPCClient(ctx context.Context) (client orderpb.OrderServiceClient, close func() error, err error) {
	if !WaitForOrderGRPCClient(viper.GetDuration("dial-grpc-timeout") * time.Second) {
		return nil, nil, errors.New("order grpc not available")
	}
	grpcAddr, err := discovery.GetServiceAddr(ctx, viper.GetString("order.service-name"))
	if err != nil {
		return nil, func() error { return nil }, err
	}
	if grpcAddr == "" {
		logrus.Warn("empty grpc addr for order grpc")
	}
	opts := grpcDialOpts(grpcAddr)
	conn, err := grpc.NewClient(grpcAddr, opts...)
	if err != nil {
		return nil, func() error { return nil }, err
	}
	return orderpb.NewOrderServiceClient(conn), conn.Close, nil
}

func grpcDialOpts(_ string) []grpc.DialOption {
	return []grpc.DialOption{
		grpc.WithTransportCredentials(insecure.NewCredentials()),
		grpc.WithStatsHandler(otelgrpc.NewClientHandler()),
	}
}
```

**payment调用**
service
```go
type OrderService interface {
	UpdateOrder(ctx context.Context, order *orderpb.Order) error
}
```
adapters
```go
type OrderGRPC struct {
	client orderpb.OrderServiceClient
}

func NewOrderGRPC(client orderpb.OrderServiceClient) *OrderGRPC {
	return &OrderGRPC{client: client}
}

func (o OrderGRPC) UpdateOrder(ctx context.Context, order *orderpb.Order) (err error) {
	ctx, span := tracing.Start(ctx, "order_grpc.update_order")
	defer span.End()

	_, err = o.client.UpdateOrder(ctx, order)
	return status.Convert(err).Err()
}
```
app
- @ 通过`orderClient`再得到的`orderGRPC`与`orderpb`无关, 属于业务层面上的向`order`发起请求的工具

```go
func NewApplication(ctx context.Context) (app.Application, func()) {
	orderClient, closeOrderClient, err := grpcClient.NewOrderGRPCClient(ctx)
	if err != nil {
		panic(err)
	}
	orderGRPC := adapters.NewOrderGRPC(orderClient)
	//memoryProcessor := processor.NewInmemProcessor()
	stripeProcessor := processor.NewStripeProcessor(viper.GetString("stripe-key"))
	return newApplication(ctx, orderGRPC, stripeProcessor), func() {
		_ = closeOrderClient()
	}
}

func newApplication(_ context.Context, orderGRPC command.OrderService, processor domain.Processor) app.Application {
	logger := logrus.StandardLogger()
	metricClient := metrics.NewPrometheusMetricsClient(&metrics.PrometheusMetricsClientConfig{
		Host:        viper.GetString("payment.metrics_export_addr"),
		ServiceName: viper.GetString("payment.service-name"),
	})
	return app.Application{
		Commands: app.Commands{
			CreatePayment: command.NewCreatePaymentHandler(processor, orderGRPC, logger, metricClient),
		},
	}
}
```
业务逻辑上的调用(CQRS)
```go
func (c createPaymentHandler) Handle(ctx context.Context, cmd CreatePayment) (string, error) {
	var err error
	defer logging.WhenCommandExecute(ctx, "CreatePaymentHandler", cmd, err)
	link, err := c.processor.CreatePaymentLink(ctx, cmd.Order)
	if err != nil {
		return "", err
	}
	newOrder, err := entity.NewValidOrder(
		cmd.Order.ID,
		cmd.Order.CustomerID,
		consts.OrderStatusWaitingForPayment,
		link,
		cmd.Order.Items,
	)
	if err != nil {
		return "", err
	}
	err = c.orderGRPC.UpdateOrder(ctx, convertor.NewOrderConvertor().EntityToProto(newOrder))
	return link, err
}

```