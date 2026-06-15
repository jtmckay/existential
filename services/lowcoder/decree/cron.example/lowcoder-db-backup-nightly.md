---
cron: "0 2 * * *"
routine: db-backup
TIER: nightly
TARGETS: |
  mongo lowcoder-mongodb LOWCODER_MONGO_ROOT_USERNAME LOWCODER_MONGO_ROOT_PASSWORD
---

Dump lowcoder-mongodb nightly and rclone to ${EXIST_BACKUP_RCLONE_REMOTE}/nightly/lowcoder-mongodb/.
Files older than 7 days are pruned at the end of the run.

Copy to decree/cron/ to activate.
