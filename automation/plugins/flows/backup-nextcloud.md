---
name: backup-nextcloud
x-exist-project: backup
x-exist-title: Back up Nextcloud
x-exist-tagline: Nextcloud, backed up nightly and weekly to your rclone remote
x-exist-docs: /docs/decree/automation-backup
x-exist-services:
  - EXIST_IS_SERVICES_AUTOMATION_BACKUP
  - EXIST_IS_NAS_NEXTCLOUD
needs:
  - db_backup
cron:
  nextcloud-db-backup-nightly.md: |
    ---
    cron: "0 2 * * *"
    machine: db_backup
    params:
      TIER: nightly
      TARGETS: |
        mariadb nextcloud-db _LITERAL_root NEXTCLOUD_ROOT_PASSWORD
    ---

    Dump nextcloud-db nightly and rclone to ${EXIST_BACKUP_RCLONE_REMOTE}/nightly/nextcloud-db/.
    Files older than 7 days are pruned at the end of the run.
  nextcloud-db-backup-weekly.md: |
    ---
    cron: "0 3 * * SUN"
    machine: db_backup
    params:
      TIER: weekly
      TARGETS: |
        mariadb nextcloud-db _LITERAL_root NEXTCLOUD_ROOT_PASSWORD
    ---

    Weekly dump of nextcloud-db (retained 28 days).
---

Backups go to the rclone remote in EXIST_BACKUP_RCLONE_REMOTE (.env.shared); add it once with
./existential.sh run rclone. Restore with ./existential.sh run backup-restore. For another
schedule, edit the cron files in services/automation-backup/machines/flow_backup_nextcloud/cron/.
