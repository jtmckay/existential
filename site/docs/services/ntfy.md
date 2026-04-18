---
sidebar_position: 9
---

# NTFY

- Source: https://github.com/binwiederhier/ntfy
- License: [Apache 2.0](https://www.apache.org/licenses/LICENSE-2.0) / [GPLv2](https://www.gnu.org/licenses/old-licenses/gpl-2.0.html)
- Alternatives: Gotify, Pushover, Apprise, Pushbullet

Simple HTTP-based pub-sub notification service. Send notifications to your phone or desktop via scripts.

## Features

- **Simple HTTP API**: Send notifications with simple HTTP POST requests
- **Authentication**: User authentication and access control
- **Multiple Topics**: Organized notification topics
- **Mobile Apps**: Native apps for Android and iOS
- **Web Interface**: Browser-based interface for managing notifications

## Getting Started

1. Copy `.env.example` to `.env` and update variables
2. Copy `server.yml.example` to `server.yml`
3. Generate password hashes/tokens (see below)
4. Run `docker-compose up -d`

## User Setup

### Compute password hash for admin

```bash
echo -n 'YourAdminPass' | docker run --rm -i httpd:2-alpine htpasswd -niB pick_a_name
```

### Compute password hash for bot

```bash
echo -n 'MyS3cret' | docker run --rm -i httpd:2-alpine htpasswd -niB bot
```

### Generate bot token

```bash
echo "tk_$(tr -dc 'a-z0-9' </dev/urandom | head -c 29)"
```

## API Usage

### Simple Notification

```bash
curl -d "Backup completed successfully" \
  -H "Authorization: Bearer tk_REPLACE_BOT_TOKEN" \
  http://localhost:36880/exist/backup
```

## Services

| Endpoint | URL |
|---|---|
| Web Interface | http://localhost:36880 |
| API | http://localhost:36880/{topic} |
| Health Check | http://localhost:36880/v1/health |

## Debugging

```bash
# List users
docker exec -it ntfy ntfy user list
```
