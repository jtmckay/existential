---
machine: plugin
automation: backup-lowcoder
project: backup
name: Back up Lowcoder
tagline: Lowcoder, backed up nightly and weekly to your rclone remote
docs: /docs/decree/automation-backup
services:
  - EXIST_IS_SERVICES_AUTOMATION_BACKUP
  - EXIST_IS_SERVICES_LOWCODER
needs:
  - db_backup
  - volume_backup
cron:
  lowcoder-db-backup-nightly: |
    ---
    cron: "0 2 * * *"
    machine: db_backup
    params:
      TIER: nightly
      TARGETS: |
        mongo lowcoder-mongodb LOWCODER_MONGO_ROOT_USERNAME LOWCODER_MONGO_ROOT_PASSWORD
    ---

    Dump lowcoder-mongodb nightly and rclone to ${EXIST_BACKUP_RCLONE_REMOTE}/nightly/lowcoder-mongodb/.
    Files older than 7 days are pruned at the end of the run.
  lowcoder-db-backup-weekly: |
    ---
    cron: "0 3 * * SUN"
    machine: db_backup
    params:
      TIER: weekly
      TARGETS: |
        mongo lowcoder-mongodb LOWCODER_MONGO_ROOT_USERNAME LOWCODER_MONGO_ROOT_PASSWORD
    ---

    Weekly dump of lowcoder-mongodb (retained 28 days).
  lowcoder-volume-backup-nightly: |
    ---
    cron: "30 2 * * *"
    machine: volume_backup
    params:
      TIER: nightly
      VOLUMES: |
        lowcoder_data         lowcoder-api-service
        lowcoder_assets_data  lowcoder-api-service,lowcoder-frontend
    ---

    Tar lowcoder volumes nightly and rclone to ${EXIST_BACKUP_RCLONE_REMOTE}/nightly/volumes/.
    Files older than 7 days are pruned at the end of the run.
  lowcoder-volume-backup-weekly: |
    ---
    cron: "30 3 * * SUN"
    machine: volume_backup
    params:
      TIER: weekly
      VOLUMES: |
        lowcoder_data         lowcoder-api-service
        lowcoder_assets_data  lowcoder-api-service,lowcoder-frontend
    ---

    Weekly tar of lowcoder volumes (retained 28 days).
---

Backups go to the rclone remote in EXIST_BACKUP_RCLONE_REMOTE (.env.shared); add it once with
./existential.sh run rclone. Restore with ./existential.sh run backup-restore. For another
schedule, edit the cron files in services/automation-backup/cron/.
