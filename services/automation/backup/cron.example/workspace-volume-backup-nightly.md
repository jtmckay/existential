---
cron: "0 3 * * *"
machine: volume_backup
params:
  TIER: nightly
  VOLUMES: |
    workspace_data nextcloud,nextcloud-cron,hermes-agent,code-server,automation
---

Tar the workspace_data volume nightly and rclone to ${EXIST_BACKUP_RCLONE_REMOTE}/nightly/volumes/workspace_data/.
Files older than 7 days are pruned at the end of the run.

Copy to services/automation/backup/cron/ and restart automation-backup to activate.
