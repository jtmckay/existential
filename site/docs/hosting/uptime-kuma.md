---
sidebar_position: 8
---

# Uptime-Kuma

- Source: https://github.com/louislam/uptime-kuma
- License: [MIT](https://opensource.org/licenses/MIT)
- Alternatives: Prometheus + Grafana, UptimeRobot, StatusCake

Self-hosted monitoring tool for service availability.

## Features

- **Multi-Protocol Monitoring**: HTTP(S), TCP, DNS, ping, and Docker container health checks
- **Public Status Pages**: Hosted status page to show uptime to users or teammates
- **90+ Notification Channels**: Telegram, Slack, email, ntfy, PagerDuty, and more
- **Response Time Graphs**: Historical latency charts and incident timeline
- **Maintenance Windows**: Silence alerts during planned downtime
- **Heartbeat Monitoring**: Detect when a cron job or script stops phoning home

## Setup Alerts

One option: Telegram bot

1. Create a bot with BotFather (built-in Telegram bot)
2. Save the API token
3. Add it as a notification option in Uptime-Kuma

## Infrastructure as Code

Configure once, restore later if necessary:

- Export/import settings via **Settings → Backup & Restore**
- Place backup into `./uptime-kuma-data/kuma.db` (mounted volume)

