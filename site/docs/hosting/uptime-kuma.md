---
sidebar_position: 8
---

# Uptime-Kuma

- Source: https://github.com/louislam/uptime-kuma
- License: [MIT](https://opensource.org/licenses/MIT)
- Alternatives: Prometheus + Grafana, UptimeRobot, StatusCake

Self-hosted monitoring tool for service availability.

## First boot is manual

Uptime-Kuma cannot self-provision. On the first visit to
`https://uptime-kuma.<domain>` it serves a setup page that creates the admin account;
there is no environment variable for it, so this is a step you do by hand. (The
database-choice page before it is skipped — the compose file pins
`UPTIME_KUMA_DB_TYPE=sqlite`.)

Monitors and notifications are likewise UI-only: v2's API serves badges and
`/metrics`, not monitor CRUD.

## Setup Alerts

Point it at the stack's own ntfy: **Settings → Notifications → Setup Notification**,
type *ntfy*, server URL `http://ntfy:80`, and the topic you want.

## Backups

v2 removed *Settings → Backup & Restore*, so the whole configuration lives in
`volumes/uptime_kuma_data/kuma.db` and nowhere else. Activate a backup by copying
`services/automation/backup/cron.example/uptime-kuma-sqlite-backup-*.md` into
`services/automation/backup/cron/` and restarting `decree-backup`.
