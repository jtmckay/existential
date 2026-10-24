---
service: services/ntfy
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
`entrypoint.sh` creates two users on first boot: your admin login, from `NTFY_ADMIN_USER` /
`NTFY_ADMIN_PASSWORD` in `services/ntfy/.env`, and the publishing bot, from `EXIST_NTFY_USER` /
`EXIST_NTFY_PASSWORD` in `.env.shared` — granted read-write on `EXIST_NTFY_TOPICS`. It waits for
ntfy to create its auth database first, since `ntfy user add` cannot run before that exists, and
it is a no-op on every later start.

Decree publishes as that user, so automations report in with no further configuration, and a
run that fails or waits for you says so on the `decree` topic ([Decree](../decree/decree#when-a-run-needs-you)).

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

## API Usage

### Simple Notification

```bash
curl -d "Backup completed successfully" \
  -H "Authorization: Bearer tk_REPLACE_BOT_TOKEN" \
  https://<machine>.<tailnet>.ts.net:8443/exist/backup
```

## Services

In Core, ntfy is on the host's tailnet name, port 8443: `./existential.sh` runs `tailscale serve`
for it, and the container publishes on loopback only. With the Caddy add-on and no tailnet name,
it is `https://ntfy.<domain>`. `entrypoint.sh` sets ntfy's base URL, the address the phone app
and ntfy's own links use, to whichever applies; `NTFY_BASE_URL` in `services/ntfy/.env`
overrides it.

| Endpoint | Core (Tailscale) | Caddy add-on |
|---|---|---|
| Web Interface | `https://<machine>.<tailnet>.ts.net:8443` | `https://ntfy.<domain>` |
| API | `https://<machine>.<tailnet>.ts.net:8443/{topic}` | `https://ntfy.<domain>/{topic}` |
| Health Check | `https://<machine>.<tailnet>.ts.net:8443/v1/health` | `https://ntfy.<domain>/v1/health` |

## Debugging

```bash
# List users
docker exec -it ntfy ntfy user list
```
