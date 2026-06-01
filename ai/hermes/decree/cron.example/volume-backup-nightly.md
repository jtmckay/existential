---
cron: "30 2 * * *"
routine: volume-backup
TIER: nightly
VOLUMES: |
  hermes_agent_data hermes-agent,hermes-workspace
---

Tar hermes_agent_data volume nightly and rclone to ${EXIST_BACKUP_RCLONE_REMOTE}/nightly/volumes/hermes_agent_data/.
Files older than 7 days are pruned at the end of the run.

Copy to decree/cron/ to activate.
