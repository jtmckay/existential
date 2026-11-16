---
machine: plugin
automation: backup-workspace
project: backup
name: Back up Your workspace
tagline: Your workspace, backed up nightly and weekly to your rclone remote
docs: /docs/decree/automation-backup
services:
  - EXIST_IS_SERVICES_AUTOMATION_BACKUP
needs:
  - volume_backup
cron:
  workspace-volume-backup-nightly: |
    ---
    cron: "0 3 * * *"
    machine: volume_backup
    params:
      TIER: nightly
      VOLUMES: |
        workspace_data nextcloud,nextcloud-cron,code-server,automation
    ---

    Tar the workspace_data volume nightly and rclone to ${EXIST_BACKUP_RCLONE_REMOTE}/nightly/volumes/workspace_data/.
    Files older than 7 days are pruned at the end of the run.
  workspace-volume-backup-weekly: |
    ---
    cron: "0 4 * * SUN"
    machine: volume_backup
    params:
      TIER: weekly
      VOLUMES: |
        workspace_data nextcloud,nextcloud-cron,code-server,automation
    ---

    Weekly tar of the workspace_data volume (retained 28 days).
---

Backups go to the rclone remote in EXIST_BACKUP_RCLONE_REMOTE (.env.shared); add it once with
./existential.sh run rclone. Restore with ./existential.sh run backup-restore. For another
schedule, edit the cron files in services/automation-backup/cron/.
