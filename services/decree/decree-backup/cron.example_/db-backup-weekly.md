---
cron: "0 3 * * 0"
routine: db-backup
TIER: weekly
---

Weekly counterpart to db-backup-nightly. Same target list, written to
`${EXIST_BACKUP_RCLONE_REMOTE}/weekly/<container>/` with a 28-day
retention window — gives you a longer-horizon recovery point in case a
problem isn't noticed within the nightly window.

Copy this file into `services/decree/decree-backup/cron/` to activate.
