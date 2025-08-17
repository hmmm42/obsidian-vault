# 特点
vs kfaka: 都基于 amqp, kfaka 性能高, 可用性高(分布式), 时效性不好(排队速度), 路由简单; rabbitMQ 路由丰富, 性能够用.
vs rocketMQ: 融合 rabbitMQ 和 kfaka.
业务背景: 时效性, 一致性
# 架构
- Broker: 可以看做RabbitMQ的服务节点, 消息代理服务器。一般请下一个Broker可以看做一个RabbitMQ服务器。负责接收, 存储, 投递, 路由消息
- Queue: RabbitMQ的内部对象，用于存储消息。多个消费者可以订阅同一队列，这时队列中的消息会被平摊（轮询）给多个消费者进行处理。
- Exchange:生产者将消息发送到交换器，由交换器将消息路由到一个或者多个队列中。当路由不到时，或返回给生产者或直接丢弃
- Exchange 和 Queue 之间是多对多的关系, 每一个`ch.QueueDeclare`绑定一种关系
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
# 消息不丢
## 生产者到MQ
是的, RabbitMQ确实提供了**事务机制(Transactional Mechanism)**, 它是早期版本中用来保证消息可靠投递的方式. 但是, 在现代的RabbitMQ应用中, 它已经**几乎完全被Publisher Confirms机制所取代**.
### 事务机制 (Transactional Mechanism)
事务机制的工作方式与数据库事务非常相似, 它提供了一种“全有或全无”的原子性保证.
**工作流程:**
1. **开启事务**: 生产者通过`tx.Select()`命令, 将当前Channel设置为事务模式.
2. **发布消息**: 在此之后, 生产者发布的所有消息都会被RabbitMQ缓存起来, 但**不会立即被路由到队列中**.
3. **提交或回滚**:
    - 生产者调用`tx.Commit()`: RabbitMQ会将这个事务中缓存的所有消息原子性地投递到对应的队列中. 只有当`Commit`成功返回, 生产者才能确定所有消息都已安全送达.
    - 生产者调用`tx.Rollback()`: RabbitMQ会安静地丢弃这个事务中缓存的所有消息.
**核心缺点: 同步阻塞, 性能极差**
事务机制最大的问题在于它的**同步阻塞**特性. `tx.Commit()`命令会阻塞生产者的线程, 直到RabbitMQ broker确认事务已经提交并返回`Commit-Ok`. 这意味着:
- **每一次事务提交, 都至少包含一次完整的网络往返(Round-Trip Time, RTT).**
- 这使得消息的发布吞吐量被网络延迟牢牢限制住. 即使在一个低延迟的局域网中, 使用事务机制的吞吐量通常也只有**每秒几百条**消息, 性能非常低下.
---
### Publisher Confirms 机制
这是RabbitMQ官方推荐的、用来替代事务的轻量级可靠投递机制.
**工作流程:**
1. **开启确认模式**: 生产者通过`ch.Confirm(false)`命令, 将Channel设置为Confirm模式.
2. **异步发布**: 生产者可以像平常一样, 以极高的速度连续调用`ch.Publish()`发布消息. 这个调用是**非阻塞的**, 它会立刻返回.
3. **异步接收回执**: RabbitMQ会为每一条(或一批)消息异步地发回一个确认信息(ack)或否认信息(nack). 生产者通过一个专门的监听通道(`notifyConfirm`)来接收这些回执, 并进行相应的处理(比如记录日志或重试).
==这里的`ack`是MQ确认收到生产者消息的`ack`==
```go
// A more robust publisher implementation
package rabbitmq

import (
	// ...
	"log"
	"sync"
	"time"
)

type ReliablePublisher struct {
	ch           *amqp.Channel
	notifyConfirm chan amqp.Confirmation
	notifyReturn  chan amqp.Return
}

func NewReliablePublisher(ch *amqp.Channel) (*ReliablePublisher, error) {
	// 1. 将Channel设置为Confirm模式
	if err := ch.Confirm(false); err != nil {
		return nil, err
	}

	p := &ReliablePublisher{
		ch:            ch,
		notifyConfirm: ch.NotifyPublish(make(chan amqp.Confirmation, 1)),
		notifyReturn:  ch.NotifyReturn(make(chan amqp.Return, 1)), // 用于处理无法路由的消息
	}

	// 2. 启动一个goroutine来异步监听确认和返回
	go p.watchConfirmations()

	return p, nil
}

func (p *ReliablePublisher) Publish(ctx context.Context, exchange, routingKey string, body []byte) error {
    // 3. 发布时, 必须将消息设置为持久化, 并开启mandatory
	err := p.ch.Publish(
		exchange,
		routingKey,
		true, // mandatory: true. 如果无法路由, 消息会返回给notifyReturn
		false,
		amqp.Publishing{
			ContentType:  "application/json",
			DeliveryMode: amqp.Persistent, // 核心: 消息持久化
			Body:         body,
		},
	)
	return err
}

func (p *ReliablePublisher) watchConfirmations() {
	log.Println("Confirmation watcher started")
	for {
		select {
		case conf := <-p.notifyConfirm:
			if conf.Ack {
				// RabbitMQ成功确认, 消息已安全接收
				// 可以记录日志, 或者更新一个待确认消息的map
				log.Printf("Message confirmed: deliveryTag %d", conf.DeliveryTag)
			} else {
				// RabbitMQ表示消息处理失败(nack)
				// 需要进行重试或记录到失败日志中, 人工干预
				log.Printf("Message failed confirmation: deliveryTag %d", conf.DeliveryTag)
			}
		case ret := <-p.notifyReturn:
			// mandatory=true时, 无法路由的消息会来到这里
			log.Printf("Message returned: from exchange %s, with routing key %s, reason: %s",
				ret.Exchange, ret.RoutingKey, ret.ReplyText)
			// 需要告警或记录日志
		}
	}
}
```
**核心优点: 异步非阻塞, 性能极高**
由于发布和确认是完全解耦和异步的, 生产者可以不间断地“流式”发布消息, 将网络带宽利用到极致, 无需等待任何同步的返回.
- **吞吐量极高**: 在同样的硬件和网络环境下, 使用Publisher Confirms的吞吐量可以轻松达到**每秒数万甚至数十万条**, 比事务机制高出**数百倍**.
---
### 详细对比与总结
|特性|**事务机制 (Not Recommended)**|**Publisher Confirms (Strongly Recommended)**|
|---|---|---|
|**性能/吞吐量**|**极低 (Very Low)**. 受限于网络RTT.|**极高 (Very High)**. 异步非阻塞, 充分利用网络带宽.|
|**协议模型**|**同步阻塞 (Synchronous)**. `tx.Commit()`会阻塞等待Broker响应.|**异步非阻塞 (Asynchronous)**. `Publish`立即返回, 确认通过回调接收.|
|**实现复杂度**|逻辑上类似数据库事务, 比较简单直接.|稍微复杂, 需要处理异步回调, 关联消息和确认.|
|**适用场景**|几乎已无适用场景, 除非你需要原子性地发布到**多个不同队列**.|**所有**需要可靠消息投递的生产环境.|

如果面试官问到这个问题, 您可以这样自信地回答:
“是的, 我了解RabbitMQ的事务机制. 它通过`tx.Select`, `tx.Commit`和`tx.Rollback`提供了一种类似数据库事务的原子性保证.
**但是, 在我的项目中, 我坚决选择了Publisher Confirms机制, 原因在于性能.**
事务机制是**同步阻塞**的, 每一次提交都会产生一次网络往返, 这使得系统的吞吐量被严重限制, 无法满足高并发的需求.
而**Publisher Confirms是异步非阻塞的**, 它允许我的生产者以极高的速率发送消息, 然后在后台异步处理Broker的确认回执. 这使得它的性能比事务机制高出**至少两个数量级**.
因此, 尽管事务机制在逻辑上更简单, 但它带来的巨大性能开销在现代应用中是不可接受的. 为了在保证消息可靠性的同时获得极致的性能, **Publisher Confirms是唯一正确的选择.**”
## MQ自身
### 持久化
默认 **经典队列**
如设置 **仲裁队列**:
```go
quorumArgs := amqp091.Table{ "x-queue-type": "quorum", }
```
#### 经典队列
==消息日志 + 队列索引 + 延迟刷盘==
1. 将消息二进制流追加到日志文件的末尾 *顺序写* **如果是小消息, 会跳过, 全部写入索引**
2. 将消息的元数据写入队列自己的索引文件 **保证 FIFO 顺序**
3. **批量地、周期性地**调用 `file:sync(File)` 系统调用, 强制操作系统将缓冲区的数据刷到物理磁盘
#### 镜像队列
简单主从复制, 已被仲裁队列取代
#### 仲裁队列
**只能用于集群**
==基于 Raft 协议 + WAL 预写日志==
1. 领导者收到消息时, 将“发布这条消息”这个**操作**封装成一个 Raft 日志条目, 写入本地 WAL
2. 领导者发送给所有跟随者, 跟随者收到后写入 WAL 并发送回执
3. 领导者收到多数节点确认后, 认为日志条目已提交, 执行`publish`
### 集群
RabbitMQ的集群主要解决了两个问题: **高可用性(High Availability)** 和 **横向扩展(Scale-out)**, 但它在实现这两个目标时有着非常鲜明的特点和取舍.
#### 第一部分: 集群的基础架构 (The Foundation)
这一部分是RabbitMQ集群不变的基石, 无论队列如何复制, 它都遵循以下原则:
1. **节点对等与元数据同步 (Peer Nodes & Metadata Sync)**:
    - RabbitMQ集群由多个独立的节点(运行`rabbitmq-server`的实例)组成.
    - 当节点加入集群后, 所有**元数据**, 包括Exchanges, Queues(的声明), Bindings, Users, vhosts等, 都会被**完整地复制到所有节点上**.
    - 这意味着, 你的客户端(生产者或消费者)可以连接到集群中的**任意一个节点**, 都能看到完全一致的"虚拟"拓扑结构. 这一点为连接层的负载均衡提供了基础.
2. **消息的归属 (Message Locality)**:
    - 这是理解RabbitMQ集群的关键. 当一个队列被创建时, 它会有一个**主副本(Leader Replica)**.
    - 所有的读写操作, 最终都会被路由到这个**Leader**所在的节点上进行协调.
    - 如果没有配置高可用复制, 那么这个队列的消息实体就只存在于Leader节点上. 一旦该节点宕机, 队列将不可用.
为了解决这个单点故障问题, RabbitMQ引入了现代化的队列复制方案.
#### 第二部分: 集群高可用的核心 - 仲裁队列 (Quorum Queues)
为了实现真正的高可用和数据安全, **仲裁队列是当今唯一被官方推荐的、现代化的解决方案**. 它从根本上取代了旧的镜像队列.
**仲裁队列的核心原理是基于分布式系统中非常成熟和可靠的Raft共识协议.**
**1. 工作原理: 基于"多数派"的共识**
- **角色**: 仲裁队列的副本不再是简单的"主/从", 而是Raft协议中的**"领导者(Leader)"**和**"追随者(Followers)"**.
- **写入流程 (保证数据不丢)**:
    1. 生产者发送一条消息, 该消息被路由到队列的Leader副本.
    2. Leader将该消息写入自己的**预写日志(WAL)**, 并将该日志条目并行地发送给所有的Followers.
    3. Leader会**一直等待**, 直到包括它自己在内的 **“多数派”(Quorum)** 节点都确认已将该日志条目**安全地写入磁盘**. 例如, 在一个有5个副本的队列中, 至少需要`(5/2) + 1 = 3`个节点确认.
    4. **只有在收到多数派确认后**, Leader才会向生产者发送`ack`, 告诉它"你的消息已安全".
- **数据安全保证**: 这个"多数派确认"机制是关键. 它保证了任何一条被生产者确认(ack'd)的消息, 都已经安全地持久化在了集群的多数节点上. 即使Leader在发送ack后立刻宕机, 这条消息也绝不会丢失.
**2. 故障转移 (保证高可用)**
- 当Leader节点因宕机或网络问题失联时, 剩下的Followers会触发一次**新的选举**.
- **Raft协议的优越性**: 只有那些拥有**最新、最全日志**的Follower节点, 才有资格被选举为新的Leader. 这从根本上杜绝了旧镜像队列中, 可能会有一个数据落后的节点被提升为新Master从而导致数据丢失的问题.
- **切换过程**: 新的Leader被选举出来后, 会接管所有读写操作. 这个过程对于正确配置的客户端来说是透明的, 它们会自动重连并继续工作, 从而保证了服务的高可用性.
#### 第三部分: 集群的类型
==默认都是磁盘节点==
根据节点的存储方式, RabbitMQ集群节点分为两种类型:
1. **磁盘节点(Disk Node)**:
    - 将元数据和消息(持久化的)都存储在磁盘上.
    - 集群中**至少需要一个**磁盘节点. 因为集群的元数据信息(比如哪个队列在哪台机器上)需要一个持久化的地方. 通常推荐配置2个或更多磁盘节点以实现元数据的高可用.
2. **内存节点(RAM Node)**:
    - 只将元数据存储在内存中 (但会从磁盘节点同步). 消息如果需要持久化, 依然会写入到它所在节点的磁盘上.
    - **优点**: 因为元数据操作(如创建队列, 绑定)不涉及磁盘I/O, 所以性能更高.
    - **缺点**: 如果一个内存节点重启, 它需要从其他磁盘节点同步集群的元数据信息.
在大多数场景下, 将==所有节点都设置为磁盘节点==是最简单和最可靠的选择. 仅在对Exchange和Queue的创建/删除操作有极致性能要求的场景下, 才考虑使用内存节点.
### 总结陈词
“RabbitMQ的现代集群机制, 是一个由**对等节点**和**Raft共识协议**驱动的精密系统.
它的基础是所有节点共享**元数据**, 这使得客户端可以连接到任意节点.
而其**高可用和数据安全的核心, 完全依赖于仲裁队列(Quorum Queues)**. 仲裁队列通过Raft协议, 实现了基于 **“多数派确认”** 的强一致性数据复制. 任何被确认写入的消息, 都保证已在多数节点上落盘, 从而**杜绝了数据丢失的风险**.
当发生节点故障时, Raft协议内置的、安全的**Leader选举机制**能保证只有数据最完整的节点才能成为新的主节点, 实现了可靠的、无缝的**故障转移**.
因此, 当我们在讨论RabbitMQ集群时, 我们实际上是在讨论如何通过部署多个节点, 并利用仲裁队列的Raft共识能力, 来构建一个真正健壮、可靠、数据安全的消息传递系统.”
# 消息顺序
会出现顺序错乱的情况:
- 多个生产者并发发布 / 多个消费者并发消费 
	- 解决: 一个生产者对应一个 channel
	- 一致性哈希, 将消息路由到不同专属队列, 每个队列分配一个消费者
- 消息重入队列
- 死信重试
# 消息类型
alpha, beta, gamma, delta
这是一个内部的状态机, 它的核心目标是: **尽可能让即将被消费的“热”数据留在内存中以获得高性能, 同时将积压的、暂不消费的“冷”数据优雅地换出到磁盘以节省内存.**
## alpha: 内存中的常客 (All in Memory)
- **定义**: **消息内容和消息索引都完整地存储在内存中.**
- **工作原理/触发条件**:
    - 当一条消息(无论是持久化还是非持久化)刚刚到达一个队列, 并且**有足够的内存**时, 它会处于alpha状态.
    - RabbitMQ会乐观地认为这条消息马上就会被消费者取走, 所以将它完全放在内存中是最快的方式.
- **性能特点**:
    - **极高**. 消费这条消息时, Broker直接从内存中读取数据并发送给消费者, 没有任何磁盘I/O, 延迟最低.
- **核心作用**: 服务于“热”数据, 为即时消费提供极致性能.
---
## beta: 内容已落盘, 索引尚在内存 (Content on Disk, Index in Memory)
- **定义**: **消息内容已经被写入到磁盘, 但其索引(包括消息ID, 路由信息, 磁盘位置指针等元数据)仍然保留在内存中.**
- **工作原理/触发条件**:
    - 这是消息从内存向磁盘**换出(page out)**过程的**第一步**.
    - 当RabbitMQ检测到内存压力增大(例如, 队列中的消息积压过多), 它会启动一个“分页进程”. 这个进程会选择一些“较冷”的alpha状态消息.
    - 它首先将这些消息的**内容(body)**写入到磁盘的`Message Store`中. 完成后, 消息就进入了beta状态.
- **性能特点**:
    - **消费性能中等**. 当消费者需要这条消息时, Broker在内存中能快速找到索引, 但需要根据索引中的磁盘位置指针, **执行一次磁盘读取**来获取消息内容. 这比alpha状态慢.
    - **内存占用降低**. 因为庞大的消息体已经不在内存里了, 只有轻量的索引信息, 所以有效释放了内存.
- **核心作用**: 这是内存到磁盘的过渡状态, 目的是快速释放由消息内容占用的内存空间.
---
## gamma: 身心俱疲, 全面落盘 (Content and Index on Disk)
- **定义**: **消息内容和它的索引都已经被写入到磁盘中.** 在RabbitMQ的内部实现中, 为了快速访问, 队列的索引本身也是分段存储的, gamma状态可以理解为消息连同它所在的索引段都一起被换出到了磁盘.
- **工作原理/触发条件**:
    - 这是消息换出过程的**第二步**, 紧随beta状态之后.
    - 当内存压力持续存在, RabbitMQ不仅会将消息内容写入磁盘, 还会决定将包含这些消息索引的**索引段(index segment)** 也从内存中清除, 并写入到磁盘的队列索引文件(`queue index file`)中.
- **性能特点**:
    - **消费性能较差**. 当消费者需要这条消息时, Broker首先需要**从磁盘读取队列索引文件**, 在其中找到消息的索引, 然后再根据索引**从磁盘读取消息内容文件**. 这个过程可能涉及**多次磁盘I/O**, 延迟最高.
    - **内存占用最低**. 消息的所有信息在内存中几乎没有残留(可能只有极少量用于队列管理的指针).
- **核心作用**: 在内存极度紧张的情况下, 将“最冷”的数据完全换出, 最大程度地节省内存.
---
## delta: 共享内容的磁盘引用 (Content on Disk, Index on Disk, Shared)
- **定义**: 这是一个特殊的gamma状态. 它特指那些通过`fanout`交换机广播给多个队列的消息. **所有队列共享磁盘上同一份消息内容**, 只是各自在自己的磁盘索引文件中记录一个对该内容的引用.
- **工作原理/触发条件**:
    - 当一个生产者向一个`fanout`交换机发布一条持久化消息, 并且这个交换机绑定了多个持久化队列时.
    - RabbitMQ非常智能, 它只会在磁盘的`Message Store`中将这条消息**写入一次**.
    - 然后, 每个队列的磁盘索引文件中, 都会创建一个指向这个**共享磁盘位置**的索引条目.
- **性能特点**:
    - 与gamma状态类似, 消费时都需要从磁盘读取.
    - **写入性能和磁盘空间利用率极高**. 避免了同一条消息被重复写入磁盘多次, 极大地节省了磁盘I/O和存储空间.
- **核心作用**: 专门优化广播(fanout)场景下的磁盘使用效率.
## 总结: 性能与资源的博弈
这四种状态构成了一个动态的生命周期, 展现了RabbitMQ作为一个成熟中间件在设计上的精妙之处:
消息生命周期:
Publish -> alpha (热) -> 内存压力 -> beta (温) -> 持续压力 -> gamma/delta (冷) -> 被消费 -> (从磁盘读取) -> Ack -> 从磁盘删除
这个状态机本质上是一个**基于LRU(最近最少使用)思想的缓存管理系统**. 它努力在**高性能(内存)** 和**大容量(磁盘)** 之间找到一个动态的平衡点, 确保系统既能快速响应, 又能处理大量的消息积压, 而不会因内存耗尽而崩溃.