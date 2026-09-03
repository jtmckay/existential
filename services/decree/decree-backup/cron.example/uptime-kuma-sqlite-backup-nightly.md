---
cron: "0 3 * * *"
routine: sqlite-backup
TIER: nightly
TARGETS: |
  kuma uptime_kuma_data/kuma.db
---

Dump uptime-kuma's SQLite database nightly (transaction-consistent, via `sqlite3 .dump`)
and rclone the gzipped SQL to ${EXIST_BACKUP_RCLONE_REMOTE}/nightly/sqlite/kuma/.
Files older than 7 days are pruned at the end of the run.

This is the only backup uptime-kuma has: v2 removed Settings → Backup & Restore, so
monitors and notifications exist nowhere but kuma.db.

Copy to services/decree/decree-backup/cron/ and restart decree-backup to activate.
