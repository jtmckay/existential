---
cron: "30 2 * * *"
routine: volume-backup
TIER: nightly
VOLUMES: |
  nocodb_data nocodb
---

Tar nocodb_data volume nightly and rclone to ${EXIST_BACKUP_RCLONE_REMOTE}/nightly/volumes/nocodb_data/.
Files older than 7 days are pruned at the end of the run.

Copy to decree/cron/ to activate.
