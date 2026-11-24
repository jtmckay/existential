---
name: backup-nocodb
x-exist-project: backup
x-exist-title: Back up NocoDB
x-exist-tagline: NocoDB, backed up nightly and weekly to your rclone remote
x-exist-docs: /docs/decree/automation-backup
x-exist-services:
  - EXIST_IS_SERVICES_AUTOMATION_BACKUP
  - EXIST_IS_SERVICES_NOCODB
needs:
  - db_backup
  - volume_backup
cron:
  nocodb-db-backup-nightly.md: |
    ---
    cron: "0 2 * * *"
    machine: db_backup
    params:
      TIER: nightly
      TARGETS: |
        postgres nocodb-postgres NOCODB_POSTGRES_USER NOCODB_POSTGRES_PASSWORD
    ---

    Dump nocodb-postgres nightly and rclone to ${EXIST_BACKUP_RCLONE_REMOTE}/nightly/nocodb-postgres/.
    Files older than 7 days are pruned at the end of the run.
  nocodb-db-backup-weekly.md: |
    ---
    cron: "0 3 * * SUN"
    machine: db_backup
    params:
      TIER: weekly
      TARGETS: |
        postgres nocodb-postgres NOCODB_POSTGRES_USER NOCODB_POSTGRES_PASSWORD
    ---

    Weekly dump of nocodb-postgres (retained 28 days).
  nocodb-volume-backup-nightly.md: |
    ---
    cron: "30 2 * * *"
    machine: volume_backup
    params:
      TIER: nightly
      VOLUMES: |
        nocodb_data nocodb
    ---

    Tar nocodb_data volume nightly and rclone to ${EXIST_BACKUP_RCLONE_REMOTE}/nightly/volumes/nocodb_data/.
    Files older than 7 days are pruned at the end of the run.
  nocodb-volume-backup-weekly.md: |
    ---
    cron: "30 3 * * SUN"
    machine: volume_backup
    params:
      TIER: weekly
      VOLUMES: |
        nocodb_data nocodb
    ---

    Weekly tar of nocodb_data volume (retained 28 days).
---

Backups go to the rclone remote in EXIST_BACKUP_RCLONE_REMOTE (.env.shared); add it once with
./existential.sh run rclone. Restore with ./existential.sh run backup-restore. For another
schedule, edit the cron files in services/automation-backup/machines/flow_backup_nocodb/cron/.
