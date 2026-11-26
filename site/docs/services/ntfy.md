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
`EXIST_NTFY_PASSWORD` in `.env.shared` — granted read-write on every topic. It waits for
ntfy to create its auth database first, since `ntfy user add` cannot run before that exists, and
it is a no-op on every later start.

Decree publishes as that user, so automations report in with no further configuration, and a
run that fails or waits for you says so ([Decree](../decree/decree.md#when-a-run-needs-you)).

### Subscribe

Install the ntfy app (or open ntfy in a browser: `https://<machine>.<tailnet>.ts.net:8443` in
Core), sign in with the admin login above, and subscribe to each topic below that you want on
your phone. Check it with `./existential.sh test ntfy`.

### Topics

Every notification the stack sends goes to one of these, and nothing else
(`./existential.sh test plugins` checks it). Each is its own path on the server,
`<ntfy address>/<topic>`, so the app lists them apart and each can be muted on its own.

| Topic | What arrives |
|---|---|
| `host` | The server: every [Grafana](../hosting/grafana.md) alert (a failed backup or host run, a backup that stopped, a container that stopped), health checks, service tests (`triage`), image and Ubuntu updates, `pull-existential`, workspace sync holding a large delete, and a failed run of any plugin tagged `x-exist-topic: host` |
| `decree` | Your automations: a run that failed or waits for you, an automation built for you to review (`develop`, `reconcile`), an agent task done, Gmail needing a new grant |
| `suggestions` | What you could turn on: [file advice](../flows/index.md#file-advice), automations proposed from a note, machines another stack offers or asks for |
| `digest` | What you read: you-were-here, look-back, the newsletter, note connections, a developed idea |
| `exist` | Whatever you POST to [automation-webhook](../decree/automation-webhook.md)'s `/notify` endpoints |

A notify call names its topic, `decree emit --machine notify --param ntfy_topic=<topic>`; a
new topic is a row here first.

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
for it, and the container publishes on loopback only. Without Tailscale it is on your network
at `http://<host-ip>:44680`. With the Caddy add-on and no tailnet name,
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
