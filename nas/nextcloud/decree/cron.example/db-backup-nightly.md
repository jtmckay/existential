---
cron: "0 2 * * *"
routine: db-backup
TIER: nightly
TARGETS: |
  mariadb nextcloud-db _LITERAL_root NEXTCLOUD_ROOT_PASSWORD
---

Dump nextcloud-db nightly and rclone to ${EXIST_BACKUP_RCLONE_REMOTE}/nightly/nextcloud-db/.
Files older than 7 days are pruned at the end of the run.

Copy to decree/cron/ to activate.
