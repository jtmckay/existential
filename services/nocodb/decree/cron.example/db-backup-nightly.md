---
cron: "0 2 * * *"
routine: db-backup
TIER: nightly
TARGETS: |
  postgres nocodb-postgres NOCODB_POSTGRES_USER NOCODB_POSTGRES_PASSWORD
---

Dump nocodb-postgres nightly and rclone to ${EXIST_BACKUP_RCLONE_REMOTE}/nightly/nocodb-postgres/.
Files older than 7 days are pruned at the end of the run.

Copy to decree/cron/ to activate.
