# 特点
vs kfaka: 都基于 amqp, kfaka 性能高, 可用性高(分布式), 时效性不好(排队速度), 路由简单; rabbitMQ 路由丰富, 性能够用.
vs rocketMQ: 融合 rabbitMQ 和 kfaka.
业务背景: 时效性, 一致性
# Exchange
接收生产者的消息, 通过路由键将消息路由到一个或多个队列
# 简单使用示例
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