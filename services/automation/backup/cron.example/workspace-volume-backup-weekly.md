---
cron: "0 4 * * 0"
routine: volume-backup
TIER: weekly
VOLUMES: |
  workspace_data nextcloud,nextcloud-cron,hermes-agent,code-server,automation
---

Weekly tar of the workspace_data volume (retained 28 days).

Copy to services/automation/backup/cron/ and restart automation-backup to activate.
