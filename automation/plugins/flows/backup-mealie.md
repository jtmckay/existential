---
name: backup-mealie
x-exist-project: backup
x-exist-title: Back up Mealie
x-exist-tagline: Mealie, backed up nightly and weekly to your rclone remote
x-exist-docs: /docs/decree/automation-backup
x-exist-services:
  - EXIST_IS_SERVICES_AUTOMATION_BACKUP
  - EXIST_IS_SERVICES_MEALIE
needs:
  - db_backup
  - volume_backup
cron:
  mealie-db-backup-nightly.md: |
    ---
    cron: "0 2 * * *"
    machine: db_backup
    params:
      TIER: nightly
      TARGETS: |
        postgres mealie-postgres MEALIE_POSTGRES_USER MEALIE_POSTGRES_PASSWORD
    ---

    Dump mealie-postgres nightly and rclone to ${EXIST_BACKUP_RCLONE_REMOTE}/nightly/mealie-postgres/.
    Files older than 7 days are pruned at the end of the run.
  mealie-db-backup-weekly.md: |
    ---
    cron: "0 3 * * SUN"
    machine: db_backup
    params:
      TIER: weekly
      TARGETS: |
        postgres mealie-postgres MEALIE_POSTGRES_USER MEALIE_POSTGRES_PASSWORD
    ---

    Weekly dump of mealie-postgres (retained 28 days).
  mealie-volume-backup-nightly.md: |
    ---
    cron: "30 2 * * *"
    machine: volume_backup
    params:
      TIER: nightly
      VOLUMES: |
        mealie_data mealie
    ---

    Tar mealie_data volume nightly and rclone to ${EXIST_BACKUP_RCLONE_REMOTE}/nightly/volumes/mealie_data/.
    Files older than 7 days are pruned at the end of the run.
  mealie-volume-backup-weekly.md: |
    ---
    cron: "30 3 * * SUN"
    machine: volume_backup
    params:
      TIER: weekly
      VOLUMES: |
        mealie_data mealie
    ---

    Weekly tar of mealie_data volume (retained 28 days).
---

Backups go to the rclone remote in EXIST_BACKUP_RCLONE_REMOTE (.env.shared); add it once with
./existential.sh run rclone. Restore with ./existential.sh run backup-restore. For another
schedule, edit the cron files in services/automation-backup/machines/flow_backup_mealie/cron/.
