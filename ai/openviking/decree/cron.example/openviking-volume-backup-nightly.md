---
cron: "0 3 * * *"
routine: volume-backup
TIER: nightly
VOLUMES: |
  openviking_data openviking
---

Tar openviking_data volume nightly and rclone to ${EXIST_BACKUP_RCLONE_REMOTE}/nightly/volumes/openviking_data/.
Files older than 7 days are pruned at the end of the run.

Copy to decree/cron/ to activate.
