---
cron: "30 2 * * *"
routine: volume-backup
TIER: nightly
VOLUMES: |
  lightrag_rag_storage_data lightrag
---

Tar lightrag_rag_storage_data volume nightly and rclone to ${EXIST_BACKUP_RCLONE_REMOTE}/nightly/volumes/lightrag_rag_storage_data/.
Files older than 7 days are pruned at the end of the run.

Copy to decree/cron/ to activate.
