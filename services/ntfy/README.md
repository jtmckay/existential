# NTFY
- Source: https://github.com/binwiederhier/ntfy
- License: [Apache 2.0](https://www.apache.org/licenses/LICENSE-2.0) & [GPLv2](https://www.gnu.org/licenses/old-licenses/gpl-2.0.html)

ntfy is a simple HTTP-based pub-sub notification service that allows you to send notifications to your phone or desktop via scripts.

## Features

- **Simple HTTP API**: Send notifications with simple HTTP POST requests
- **Authentication**: Configured with user authentication and access control
- **Multiple Topics**: Support for organized notification topics
- **Mobile Apps**: Native apps for Android and iOS
- **Web Interface**: Browser-based interface for managing notifications
- **Queue Integration**: Works with RabbitMQ webhook bridge for queue-based notifications

## Getting started
- Copy `.env.example` to `.env`
- Update variables
- Copy `server.yml.example` to `server.yml`
- Compute and generate password hashes/tokens [reference](#compute-password-hash-for-admin)
- Update variables
- From working directory `existential/services/ntfy` run `docker-compose up -d`

## Configuration
`./ntfy-config/server.yml`

### Users

The service is configured with two users:
- `pick_a_name`: Admin user with full access
- `bot`: Service user for automated notifications

### Authentication Token

#### Compute password hash for admin
`echo -n 'YourAdminPass' | docker run --rm -i httpd:2-alpine htpasswd -niB pick_a_name`

#### Compute password hash for bot
`echo -n 'MyS3cret' | docker run --rm -i httpd:2-alpine htpasswd -niB bot`

#### Generate bot token
`echo "tk_$(tr -dc 'a-z0-9' </dev/urandom | head -c 29)"`

### Topics and Access Control

- `bot:sensors*:rw`: Bot can read/write to sensors-related topics

## Queue Integration

ntfy integrates with the RabbitMQ webhook bridge to receive notifications from message queues. The webhook bridge is configured in the RabbitMQ service.

### Bridge Configuration

The RabbitMQ webhook bridge is configured in `/services/rabbitMQ/bridge.config.json`. [See README.md](../rabbitMQ/webhook-bridge/README.md)

### Sending Notifications via Queue

Send messages to the `notifications` queue in RabbitMQ, and use the webhook bridge to forward to ntfy:

For more details on the webhook bridge configuration, see the [RabbitMQ service documentation](../rabbitMQ/README.md).

### Notification with Title and Priority through RabbitMQ
```bash
curl -u rabbitmq:super-secret-password \
  -H "Content-Type: application/json" \
  -X POST http://localhost:5672/api/exchanges/%2F/amq.default/publish \
  -d '{"properties":{},"routing_key":"notifications","payload":"{\"pathSuffix\":\"-test\",\"body\":\"High CPU usage\",\"headers\":{\"title\":\"System Alert\",\"priority\":\"urgent\"}}","payload_encoding":"string"}'
```

## API Usage

### Simple Notification
```bash
curl -d "Backup completed successfully" \
  -H "Authorization: Bearer tk_REPLACE_BOT_TOKEN" \
  http://10.0.0.10:36880/exist/backup
```

## Client Setup

1. Install the ntfy app on your device
2. Subscribe to topics like `sensors/notifications`
3. Receive instant push notifications

## Services

- **Web Interface**: http://10.0.0.10:36880
- **API Endpoint**: http://10.0.0.10:36880/{topic}
- **Health Check**: http://10.0.0.10:36880/v1/health

# Debugging
#### List users
- `docker exec -it ntfy ntfy user list`
- Should look something like: ```
user admin (role: admin, tier: none, server config)
- read-write access to all topics (admin role)
user bot (role: user, tier: none, server config)
- read-write access to topic notifications* (server config)
user * (role: anonymous, tier: none)
- no topic-specific permissions
- no access to any (other) topics (server config)
```
