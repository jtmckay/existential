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
That is the whole setup. ntfy's `server.yml` denies every publish by default, so a fresh
install would otherwise accept nothing until someone ran a manual command — which is exactly
the sort of step that gets missed and then looks like a broken notification path. Its
`entrypoint.sh` creates the admin user and the publishing bot on first boot from
`EXIST_NTFY_USER` / `EXIST_NTFY_PASSWORD` in `.env.shared`, and grants the bot read-write on
`EXIST_NTFY_TOPICS`. It waits for ntfy to create its auth database first, since `ntfy user add`
cannot run before that exists, and it is a no-op on every later start.

Decree publishes as that user, so automations report in with no further configuration.

### Using a token instead

`EXIST_NTFY_TOKEN` takes precedence over the user and password when it is set, and ships blank.
To mint one:

```bash
./existential.sh run ntfy setup
```

Leave it blank unless you want a token — a value ntfy does not recognise fails every publish with
a 401, and because the token wins, the working user/password path is never tried.

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
