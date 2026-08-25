---
sidebar_position: 9
---

# NTFY

- Source: https://github.com/binwiederhier/ntfy
- License: [Apache 2.0](https://www.apache.org/licenses/LICENSE-2.0) / [GPLv2](https://www.gnu.org/licenses/old-licenses/gpl-2.0.html)
- Alternatives: Gotify, Pushover, Apprise, Pushbullet

Simple HTTP-based pub-sub notification service. Send notifications to your phone or desktop via scripts.

## Getting Started

1. Enable it in `.env.shared`:
   ```
   EXIST_IS_SERVICES_NTFY=true
   ```
2. Render and start, from the repo root:
   ```bash
   ./existential.sh && docker compose up -d
   ```
3. Create the admin and bot users and issue a bot token:
   ```bash
   ./existential.sh run ntfy setup
   ```
   This writes `EXIST_NTFY_URL` and `EXIST_NTFY_TOKEN` to the root `.env` so decree and
   other services can send notifications.

### Customization

Ntfy emojis: https://docs.ntfy.sh/emojis/

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
