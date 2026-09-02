---
cron: "0 4 * * 0"
routine: sqlite-backup
TIER: weekly
TARGETS: |
  kuma uptime_kuma_data/kuma.db
---

Weekly dump of uptime-kuma's SQLite database to
${EXIST_BACKUP_RCLONE_REMOTE}/weekly/sqlite/kuma/ (retained 28 days).

This is the only backup uptime-kuma has: v2 removed Settings → Backup & Restore, so
monitors and notifications exist nowhere but kuma.db.

Copy to services/decree/decree-backup/cron/ and restart decree-backup to activate.
