---
cron: "0 2 * * *"
routine: db-backup
TIER: nightly
TARGETS: |
  postgres immich-postgres DB_USERNAME DB_PASSWORD
---

Dump immich-postgres nightly and rclone to ${EXIST_BACKUP_RCLONE_REMOTE}/nightly/immich-postgres/.
Files older than 7 days are pruned at the end of the run.

DB_USERNAME/DB_PASSWORD are immich's own (unprefixed — `.env.exist` is
convention-exempt: upstream-env) and land in decree-backup's environment via
the master `.env`, same as every other service here.

Copy to services/automation/backup/cron/ and restart automation-backup to activate.
