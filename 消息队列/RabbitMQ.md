# 特点
vs kfaka: 都基于 amqp, kfaka 性能高, 可用性高(分布式), 时效性不好(排队速度), 路由简单; rabbitMQ 路由丰富, 性能够用.
vs rocketMQ: 融合 rabbitMQ 和 kfaka.
业务背景: 时效性, 一致性
# Exchange
==多个 queue 可以绑定到一个 exchange==
接收生产者的消息, 通过路由键将消息路由到一个或多个队列
使用时先声明`ExchangeDeclare`
publish 时需要提供 key 和 exchange
==如果指定 Exchange 为空，那么消息会直接路由到名称与消息的路由键完全相同的队列==
操作: `QueueBind`
## Direct 
消息的路由键（routing key）必须与队列绑定到该 Direct Exchange 上的绑定键（binding key）**完全匹配**，消息才会被路由到该队列。
## Topic
**路由规则:** 消息的路由键可以使用通配符进行模式匹配。队列在绑定到 Topic Exchange 时也可以使用通配符作为绑定键。
- `*` (星号): 匹配一个单词。
- `#` (井号): 匹配零个或多个单词。
- 单词之间通常用 `.` (点号) 分隔。
## Fanout
不会解析路由键。它会将接收到的所有消息**广播**到所有绑定到该 Exchange 的队列。
**key 会被忽略**
## Headers
根据消息的头部信息（headers）进行匹配。队列在绑定时可以指定一组 **键值对** 作为匹配规则。
- any: 只要消息头部中包含任意一个绑定指定的键值对就匹配
- all: 需要包含全部信息
# 简单使用示例
**并非强制要求生产者必须声明队列。** 如果消费者在生产者之前声明了队列，那么当生产者发布消息时，队列已经存在
## 生产者
```go
package main

import (
	"context"
	"fmt"
	"log"
	"time"

	amqp "github.com/rabbitmq/amqp091-go"
)

func main() {
	// RabbitMQ 服务器的连接地址
	amqpURL := "amqp://guest:guest@localhost:5672/"

	// 建立连接
	conn, err := amqp.Dial(amqpURL)
	if err != nil {
		log.Fatalf("Failed to connect to RabbitMQ: %v", err)
	}
	defer conn.Close()

	// 创建通道
	ch, err := conn.Channel()
	if err != nil {
		log.Fatalf("Failed to open a channel: %v", err)
	}
	defer ch.Close()

	// 声明队列
	queueName := "my_queue"
	q, err := ch.QueueDeclare(
		queueName, // name
		false,     // durable
		false,     // delete when unused
		false,     // exclusive
		false,     // no-wait
		nil,       // arguments
	)
	if err != nil {
		log.Fatalf("Failed to declare a queue: %v", err)
	}

	// 要发送的消息
	body := "Hello, RabbitMQ!"

	// 发布消息
	err = ch.PublishWithContext(
		context.Background(),
		"",         // exchange
		q.Name,    // routing key
		false,      // mandatory
		false,      // immediate
		amqp.Publishing{
			ContentType: "text/plain",
			Body:        []byte(body),
		})
	if err != nil {
		log.Fatalf("Failed to publish a message: %v", err)
	}

	log.Printf(" [x] Sent %s", body)
}
```
参数说明:
`ch.QueueDeclare()` 声明队列
- `name`: 队列的名称 (`my_queue`).
- `durable`: 如果设置为 `true`，队列在服务器重启后仍然存在。
- `delete when unused`: 如果设置为 `true`，当最后一个订阅的消费者取消订阅后，队列将被删除。
- `exclusive`: 如果设置为 `true`，队列只对声明它的连接可见，并且在该连接关闭后将被删除。
- `no-wait`: 如果设置为 `true`，声明队列的请求将不会等待服务器的响应。
- `arguments`: 用于传递额外的参数，例如设置队列的 TTL (Time-To-Live)。

`ch.PublishWithContext()` 发布消息
- `ctx`: 上下文，用于控制操作的生命周期。
- `exchange`: 消息发送到的交换机的名称。空字符串 (`""`) 表示使用默认的匿名交换机。当使用匿名交换机时，消息会直接路由到名称与路由键相同的队列。
- `routing key`: 路由键，用于交换机将消息路由到相应的队列。在使用默认交换机时，路由键通常设置为队列的名称。
- `mandatory`: 如果设置为 `true`，当消息无法路由到任何队列时，服务器会将消息返回给生产者。
- `immediate`: 如果设置为 `true`，当消息发送到至少一个消费者，但该消费者没有准备好立即接收消息时，服务器会将消息返回给生产者。这个标志在 AMQP 0-9-1 中已被标记为不推荐使用。
- `amqp.Publishing`: 包含消息的属性，例如 `ContentType` 和 `Body`。
## 消费者 
```go
package main

import (
	"fmt"
	"log"
	"os"
	"os/signal"
	"syscall"

	amqp "github.com/rabbitmq/amqp091-go"
)

func main() {
	// RabbitMQ 服务器的连接地址
	amqpURL := "amqp://guest:guest@localhost:5672/"

	// 建立连接
	conn, err := amqp.Dial(amqpURL)
	if err != nil {
		log.Fatalf("Failed to connect to RabbitMQ: %v", err)
	}
	defer conn.Close()

	// 创建通道
	ch, err := conn.Channel()
	if err != nil {
		log.Fatalf("Failed to open a channel: %v", err)
	}
	defer ch.Close()

	// 声明队列 (确保与生产者的声明匹配)
	queueName := "my_queue"
	q, err := ch.QueueDeclare(
		queueName, // name
		false,     // durable
		false,     // delete when unused
		false,     // exclusive
		false,     // no-wait
		nil,       // arguments
	)
	if err != nil {
		log.Fatalf("Failed to declare a queue: %v", err)
	}

	// 订阅队列以接收消息
	msgs, err := ch.Consume(
		q.Name, // queue
		"",     // consumer
		true,   // auto-ack
		false,  // exclusive
		false,  // no-local
		false,  // no-wait
		nil,    // args
	)
	if err != nil {
		log.Fatalf("Failed to register a consumer: %v", err)
	}

	var forever chan struct{}

	go func() {
		for d := range msgs {
			log.Printf(" [x] Received a message: %s", d.Body)
		}
	}()

	log.Printf(" [*] Waiting for messages. To exit press CTRL+C")

	// 监听中断信号，优雅地关闭连接
	signalChan := make(chan os.Signal, 1)
	signal.Notify(signalChan, syscall.SIGINT, syscall.SIGTERM)
	<-signalChan

	log.Println("Shutting down consumer...")
	close(forever)
}
```
`ch.Consume()` 订阅队列并接收消息
- `queue`: 要消费的队列的名称 (`q.Name`).
- `consumer`: 消费者的标识符。通常留空，RabbitMQ 会自动生成一个。
- `auto-ack`: 如果设置为 `true`，消费者在接收到消息后会自动向 RabbitMQ 服务器发送确认。如果设置为 `false`，消费者需要显式地发送确认（这对于确保消息处理的可靠性很重要）。
- `exclusive`: 如果设置为 `true`，只有声明该消费者的连接才能消费该队列的消息。
- `no-local`: 如果设置为 `true`，禁止接收由同一个连接（即同一个生产者）发布的消息。
- `no-wait`: 如果设置为 `true`，消费者的订阅请求将不会等待服务器的响应。
- `args`: 用于传递额外的参数。
# 死信队列
在消息驱动的系统中，死信队列是一个非常重要的容错和兜底机制。它的核心作用是处理那些无法被正常消费的消息，充当一个“消息暂存墓地”。

一个消息无法被正常消费，可能的原因有：
- 持续性处理失败：消费者在处理消息时，由于代码bug、依赖的服务长时间不可用、或业务逻辑错误，导致反复失败。
- 消息格式错误：消息体格式错误，导致消费者无法解析。这种消息通常被称为“毒丸消息 (Poison Pill)”。
- 消息过期 (TTL)：消息在队列中的存留时间超过了其设定的生命周期。
  队列达到最大长度。

如果没有死信队列，这些无法处理的消息可能会被无限次地重试，阻塞队列，影响后续正常消息的处理；或者在重试几次后被丢弃，导致数据丢失。
死信队列的好处：
- 防止消息丢失：将处理失败的消息转移到死信队列中保存，而不是直接丢弃，为后续的人工干预、问题排查和数据恢复提供了可能。
- 保障主流程通畅：将“问题消息”从主队列中移除，确保主业务流程不受“毒丸消息”的影响。 
- 监控与告警：可以监控死信队列中的消息数量。如果DLQ中有新消息进入，通常意味着系统出现了需要关注的异常，可以触发告警。
## 实现方式
### 原生 DLX
```go
package main

import (
	"context"
	"log"
	"time"

	"github.com/rabbitmq/amqp091-go"
)

func failOnError(err error, msg string) {
	if err != nil {
		log.Panicf("%s: %s", msg, err)
	}
}

// setupDLX 封装了设置死信队列所需的所有声明和绑定操作
func setupDLX(ch *amqp091.Channel) {
	// --- 定义交换机和队列的名称 ---
	mainExchange := "main_exchange" // 主交换机（非必须，可以直接发给队列）
	mainQueue := "main_queue"
	dlxExchange := "dlx_exchange" // 死信交换机
	dlxQueue := "dlx_queue"       // 死信队列

	// --- 步骤 1: 声明死信交换机 (DLX) ---
	// 类型通常为 fanout 或 direct。fanout 会将消息广播给所有绑定的队列。
	err := ch.ExchangeDeclare(
		dlxExchange, // name
		"fanout",    // type
		true,        // durable
		false,       // auto-deleted
		false,       // internal
		false,       // no-wait
		nil,         // arguments
	)
	failOnError(err, "Failed to declare DLX exchange")
	log.Printf("✅ 死信交换机 [%s] 声明成功", dlxExchange)

	// --- 步骤 2: 声明死信队列 (DLQ) ---
	_, err = ch.QueueDeclare(
		dlxQueue, // name
		true,     // durable
		false,    // delete when unused
		false,    // exclusive
		false,    // no-wait
		nil,      // arguments
	)
	failOnError(err, "Failed to declare DLQ queue")
	log.Printf("✅ 死信队列 [%s] 声明成功", dlxQueue)

	// --- 步骤 3: 绑定 DLX 和 DLQ ---
	err = ch.QueueBind(
		dlxQueue,    // queue name
		"",          // routing key (fanout类型交换机无需指定)
		dlxExchange, // exchange
		false,
		nil,
	)
	failOnError(err, "Failed to bind DLQ queue to DLX exchange")
	log.Printf("✅ 死信队列和死信交换机绑定成功")

	// --- 步骤 4: 声明主队列，并为其指定死信交换机 ---
	// 这是最关键的一步
	args := amqp091.Table{
		// 当消息变成死信时，它将被发送到这个交换机
		"x-dead-letter-exchange": dlxExchange,
		// (可选) 指定发送到DLX时使用的 routing-key。如果不指定，则使用消息原始的 routing-key。
		// "x-dead-letter-routing-key": "some-dlx-routing-key",
	}
	_, err = ch.QueueDeclare(
		mainQueue, // name
		true,      // durable
		false,     // delete when unused
		false,     // exclusive
		false,     // no-wait
		args,      // arguments: 在这里附加DLX信息
	)
	failOnError(err, "Failed to declare main queue")
	log.Printf("✅ 主队列 [%s] 声明成功，并已绑定死信交换机", mainQueue)

	// (可选) 如果你使用交换机向主队列发消息，也需要声明和绑定
	err = ch.ExchangeDeclare(mainExchange, "direct", true, false, false, false, nil)
	failOnError(err, "Failed to declare main exchange")
	err = ch.QueueBind(mainQueue, "main-key", mainExchange, false, nil)
	failOnError(err, "Failed to bind main queue")
}

// publishToMainQueue 发布一条消息
func publishToMainQueue(ch *amqp091.Channel) {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	body := "这是一条注定要失败的消息"
	err := ch.PublishWithContext(ctx,
		"main_exchange", // exchange
		"main-key",      // routing key
		false,           // mandatory
		false,           // immediate
		amqp091.Publishing{
			ContentType: "text/plain",
			Body:        []byte(body),
		},
	)
	failOnError(err, "Failed to publish a message")
	log.Printf("📤 已向主队列发送消息: %s", body)
}

// consumeAndReject 消费并拒绝消息，使其成为死信
func consumeAndReject(ch *amqp091.Channel) {
	msgs, err := ch.Consume(
		"main_queue", // queue
		"consumer-1", // consumer
		false,        // auto-ack: 必须为 false
		false,        // exclusive
		false,        // no-local
		false,        // no-wait
		nil,          // args
	)
	failOnError(err, "Failed to register a consumer")

	log.Println("🤔 消费者正在等待主队列消息...")
	msg := <-msgs // 获取一条消息
	log.Printf("🔥 主队列消费者收到消息: %s", msg.Body)

	// 拒绝消息，并设置 requeue=false，使其进入死信队列
	// Nack(deliveryTag, multiple, requeue)
	err = msg.Nack(false, false, false)
	if err != nil {
		log.Printf("❌ 拒绝消息失败: %s", err)
	} else {
		log.Println("❌ 消息已被拒绝 (requeue=false)，将被送往DLX")
	}
}

// consumeDLQ 消费死信队列，验证结果
func consumeDLQ(ch *amqp091.Channel) {
	msgs, err := ch.Consume(
		"dlx_queue",  // queue
		"dlx-consumer", // consumer
		true,         // auto-ack: 这里为了方便设为true
		false,        // exclusive
		false,        // no-local
		false,        // no-wait
		nil,          // args
	)
	failOnError(err, "Failed to register a DLQ consumer")

	log.Println("🕵️ 死信队列消费者启动，等待接收死信...")
	msg := <-msgs
	log.Printf("🎉🎉🎉 成功在死信队列 [%s] 收到消息: %s", "dlx_queue", msg.Body)
	// 还可以检查消息的 x-death header 来获取死信原因
	// log.Printf("死信原因: %+v", msg.Headers)
}

func main() {
	// 1. 建立连接和通道
	conn, err := amqp091.Dial("amqp://guest:guest@localhost:5672/")
	failOnError(err, "Failed to connect to RabbitMQ")
	defer conn.Close()

	ch, err := conn.Channel()
	failOnError(err, "Failed to open a channel")
	defer ch.Close()

	// 2. 设置所有队列和交换机
	setupDLX(ch)

	// 3. 启动一个goroutine来消费死信队列，以便验证
	go consumeDLQ(ch)

    // 等待一秒确保死信队列的消费者已经准备就绪
    time.Sleep(1 * time.Second)

	// 4. 发布一条消息到主队列
	publishToMainQueue(ch)

	// 5. 启动消费者来处理并拒绝这条消息
	consumeAndReject(ch)

	log.Println("演示完成。")
}
```
### 手动实现
```go
// internal/common/broker/rabbitmq.go

const (
	DLX                = "dlx"
	DLQ                = "dlq"
	amqpRetryHeaderKey = "x-retry-count"
)

// ...

func createDLX(ch *amqp.Channel) error {
	q, err := ch.QueueDeclare("share_queue", true, false, false, false, nil)
	if err != nil {
		return err
	}
	err = ch.ExchangeDeclare(DLX, "fanout", true, false, false, false, nil)
	if err != nil {
		return err
	}
	err = ch.QueueBind(q.Name, "", DLX, false, nil)
	if err != nil {
		return err
	}
	// 声明了一个名为 "dlq" 的持久化队列，用作死信队列
	_, err = ch.QueueDeclare(DLQ, true, false, false, false, nil)
	return err
}
```
手动重试与死信投递逻辑:
```go
// internal/common/broker/rabbitmq.go

var (
	maxRetryCount int64 = viper.GetInt64("rabbitmq.max-retry")
)

// ...

func HandleRetry(ctx context.Context, ch *amqp.Channel, d *amqp.Delivery) (err error) {
	// ... (日志记录) ...

	if d.Headers == nil {
		d.Headers = amqp.Table{}
	}
	// 1. 从消息头获取当前重试次数，如果不存在则为0
	retryCount, ok := d.Headers[amqpRetryHeaderKey].(int64)
	if !ok {
		retryCount = 0
	}
	// 2. 重试次数加一
	retryCount++
	d.Headers[amqpRetryHeaderKey] = retryCount
	fields["retry_count"] = retryCount

	// 3. 判断是否达到最大重试次数
	if retryCount >= maxRetryCount {
		// 如果达到最大次数，不再重试，将消息投递到死信队列
		logging.Infof(ctx, nil, "moving message %s to dlq", d.MessageId)
		return doPublish(ctx, ch, "", DLQ, false, false, amqp.Publishing{
			Headers:      d.Headers,
			ContentType:  "application/json",
			Body:         d.Body,
			DeliveryMode: amqp.Persistent,
		})
	}

	// 4. 如果未达到最大次数，执行重试
	logging.Debugf(ctx, nil, "retrying message %s, count=%d", d.MessageId, retryCount)
	// 简单的延迟策略，重试次数越多，延迟越长
	time.Sleep(time.Second * time.Duration(retryCount))
	// 将消息重新发布到其原始的 Exchange 和 RoutingKey
	return doPublish(ctx, ch, d.Exchange, d.RoutingKey, false, false, amqp.Publishing{
		Headers:      d.Headers,
		ContentType:  "application/json",
		Body:         d.Body,
		DeliveryMode: amqp.Persistent,
	})
}
```
# 持久化
默认 **经典队列**
如设置 **仲裁队列**:
```go
quorumArgs := amqp091.Table{ "x-queue-type": "quorum", }
```
## 经典队列
==消息日志 + 队列索引 + 延迟刷盘==
1. 将消息二进制流追加到日志文件的末尾 *顺序写* **如果是小消息, 会跳过, 全部写入索引**
2. 将消息的元数据写入队列自己的索引文件 **保证 FIFO 顺序**
3. **批量地、周期性地**调用 `file:sync(File)` 系统调用, 强制操作系统将缓冲区的数据刷到物理磁盘
## 仲裁队列
==基于 Raft 协议 + WAL 预写日志==
1. 领导者收到消息时, 将“发布这条消息”这个**操作**封装成一个 Raft 日志条目, 写入本地 WAL
2. 领导者发送给所有跟随者, 跟随者收到后写入 WAL 并发送回执
3. 领导者收到多数节点确认后, 认为日志条目已提交, 执行`publish`
# 消息顺序
会出现顺序错乱的情况:
- 多个生产者并发发布 / 多个消费者并发消费 
	- 解决: 一个生产者对应一个 channel
	- 一致性哈希, 将消息路由到不同专属队列, 每个队列分配一个消费者
- 消息重入队列
- 死信重试