---
cron: "30 2 * * *"
routine: volume-backup
TIER: nightly
VOLUMES: |
  lowcoder_data   lowcoder-api-service
  lowcoder_assets lowcoder-api-service,lowcoder-frontend
---

Tar lowcoder volumes nightly and rclone to ${EXIST_BACKUP_RCLONE_REMOTE}/nightly/volumes/.
Files older than 7 days are pruned at the end of the run.

Copy to decree/cron/ to activate.
