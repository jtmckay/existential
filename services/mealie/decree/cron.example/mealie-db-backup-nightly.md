---
cron: "0 2 * * *"
routine: db-backup
TIER: nightly
TARGETS: |
  postgres mealie-postgres MEALIE_POSTGRES_USER MEALIE_POSTGRES_PASSWORD
---

Dump mealie-postgres nightly and rclone to ${EXIST_BACKUP_RCLONE_REMOTE}/nightly/mealie-postgres/.
Files older than 7 days are pruned at the end of the run.

Copy to decree/cron/ to activate.
