---
name: backup-appsmith
x-exist-project: backup
x-exist-title: Back up Appsmith
x-exist-tagline: Appsmith, backed up nightly and weekly to your rclone remote
x-exist-docs: /docs/decree/automation-backup
x-exist-services:
  - EXIST_IS_SERVICES_AUTOMATION_BACKUP
  - EXIST_IS_SERVICES_APPSMITH
needs:
  - volume_backup
cron:
  appsmith-volume-backup-nightly.md: |
    ---
    cron: "30 2 * * *"
    machine: volume_backup
    params:
      TIER: nightly
      VOLUMES: |
        appsmith_data appsmith
    ---

    Tar appsmith_data volume nightly and rclone to ${EXIST_BACKUP_RCLONE_REMOTE}/nightly/volumes/appsmith_data/.
    Files older than 7 days are pruned at the end of the run.
  appsmith-volume-backup-weekly.md: |
    ---
    cron: "30 3 * * SUN"
    machine: volume_backup
    params:
      TIER: weekly
      VOLUMES: |
        appsmith_data appsmith
    ---

    Weekly tar of appsmith_data volume (retained 28 days).
---

Backups go to the rclone remote in EXIST_BACKUP_RCLONE_REMOTE (.env.shared); add it once with
./existential.sh run rclone. Restore with ./existential.sh run backup-restore. For another
schedule, edit the cron files in services/automation-backup/machines/flow_backup_appsmith/cron/.
