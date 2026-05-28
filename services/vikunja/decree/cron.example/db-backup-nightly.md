---
cron: "0 2 * * *"
routine: db-backup
TIER: nightly
TARGETS: |
  postgres vikunja-db VIKUNJA_DATABASE_USER VIKUNJA_DATABASE_PASSWORD
---

Dump vikunja-db nightly and rclone to ${EXIST_BACKUP_RCLONE_REMOTE}/nightly/vikunja-db/.
Files older than 7 days are pruned at the end of the run.

Copy to decree/cron/ to activate.
