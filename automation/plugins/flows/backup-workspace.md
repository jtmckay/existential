---
name: backup-workspace
x-exist-project: backup
x-exist-title: Back up Your workspace
x-exist-tagline: Your workspace, backed up nightly and weekly to your rclone remote
x-exist-docs: /docs/decree/automation-backup
x-exist-services:
  - EXIST_IS_SERVICES_AUTOMATION_BACKUP
needs:
  - volume_backup
cron:
  workspace-volume-backup-nightly.md: |
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
  workspace-volume-backup-weekly.md: |
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
schedule, edit the cron files in services/automation-backup/machines/flow_backup_workspace/cron/.
