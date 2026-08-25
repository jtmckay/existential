---
sidebar_position: 8
---

# Uptime-Kuma

- Source: https://github.com/louislam/uptime-kuma
- License: [MIT](https://opensource.org/licenses/MIT)
- Alternatives: Prometheus + Grafana, UptimeRobot, StatusCake

Self-hosted monitoring tool for service availability.

## Setup Alerts

One option: Telegram bot

1. Create a bot with BotFather (built-in Telegram bot)
2. Save the API token
3. Add it as a notification option in Uptime-Kuma

## Infrastructure as Code

Configure once, restore later if necessary:

- Export/import settings via **Settings → Backup & Restore**
- Place backup into `./uptime-kuma-data/kuma.db` (mounted volume)

