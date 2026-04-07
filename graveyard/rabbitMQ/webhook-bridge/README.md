# RabbitMQ Webhook Bridge
Subscribes to n number of queues, and posts the messages to the configured http/https endpoint.

## Configuration
- Configure by mounting a file to `/app/config.json`.
- EG in docker compose under volumes: `./bridge.config.json:/app/config.json:ro`

### RabbitMQ
#### URL
- The connection string for RabbitMQ
- EG: `amqp://admin:admin@rabbitmq:5672/%2f`

### Webhooks

#### Plain text (non-JSON)
- If the message is not JSON parsible it will simply be forwarded as the body in its entirety.

#### Body
- If the message is a JSON object with a `body`
- `body` will be forwarded as the body of the post.

#### Headers
- If there is a body
- `headers` will be passed into the request as headers.

#### Path suffix
- If there is a body
- `pathSuffix` will be concatenated to the end of the configured endpoint URL.
