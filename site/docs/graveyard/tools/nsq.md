---
sidebar_position: 6
---

# NSQ

- Source: https://github.com/nsqio/nsq
- License: [MIT](https://opensource.org/licenses/MIT)
- Alternatives: RabbitMQ, Apache Kafka, NATS, Redis Streams
- Status: Replaced by RabbitMQ (MQTT)

Queue service. Allows responding to events in a distributed way — publishers like MinIO don't need to know about subscribers, so you can create N subscribers that respond to file events without changing MinIO.
