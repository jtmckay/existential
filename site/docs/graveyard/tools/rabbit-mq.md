---
sidebar_position: 7
---

# RabbitMQ

- Source: https://github.com/rabbitmq/rabbitmq-server
- License: [MPL 2.0](https://www.mozilla.org/MPL/2.0/) / [Apache 2.0](http://www.apache.org/licenses/LICENSE-2.0)
- Alternatives: NSQ, Kafka
- Status: Replaced by ntfy and direct webhooks

Full-featured AMQP message broker with a universal webhook bridge for forwarding queue messages to HTTP endpoints and ntfy.

## Features

- **RabbitMQ Message Broker**: AMQP with SSL/TLS and MQTT support
- **Universal Webhook Bridge**: Forward messages from queues to HTTP/HTTPS webhooks and ntfy
- **Per-Endpoint Authentication**: Different auth tokens per endpoint
- **Custom Headers**: Add custom headers per endpoint

## Quick Setup

1. Copy `.env.example` to `.env`
2. Copy `bridge.config.json.example` to `bridge.config.json`
3. Configure webhook endpoints in `bridge.config.json`
4. Add configured queues to `defs.json`
5. Run `docker-compose up -d`

## Message Examples

### Send to ntfy

```bash
curl -u rabbitmq:password -H "Content-Type: application/json" -X POST \
  http://localhost:5672/api/exchanges/%2F/amq.default/publish \
  -d '{"properties":{},"routing_key":"notifications","payload":"{\"body\":\"Alert\",\"headers\":{\"title\":\"System Alert\",\"priority\":\"urgent\"}}","payload_encoding":"string"}'
```

## Ports

| Service       | Port                     |
| ------------- | ------------------------ |
| AMQP          | 5672 (plain), 5671 (SSL) |
| MQTT          | 1883 (plain), 8883 (SSL) |
| Management UI | 15672                    |
