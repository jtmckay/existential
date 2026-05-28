---
cron: "30 2 * * *"
routine: volume-backup
TIER: nightly
VOLUMES: |
  actual_budget_data actual-budget
---

Tar actual_budget_data volume nightly and rclone to ${EXIST_BACKUP_RCLONE_REMOTE}/nightly/volumes/actual_budget_data/.
Files older than 7 days are pruned at the end of the run.

Copy to decree/cron/ to activate.
