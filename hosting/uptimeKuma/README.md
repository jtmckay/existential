# Uptime-Kuma
https://github.com/louislam/uptime-kuma

Self-hosted monitoring tool

## Setup alerts
An option: Telegram bot
- Create a bot with the bot_father (built-in telegram bot)
- Save the API token somewhere safe
- Add it as a notification option in uptime-kuma, and use it for alerts

## Infra as code
- Configure it once, then restore those settings later if necessary.
- Export/import your uptime settings via Settings -> Backup & Restore.
- Place the back into `./uptime-kuma-data/kuma.db` (in the mounted volume for the container)

# Alts
- Prometheus & Grafana
- https://uptimerobot.com/
- https://www.statuscake.com/
