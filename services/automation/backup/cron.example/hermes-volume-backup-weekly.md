---
cron: "30 3 * * SUN"
machine: volume_backup
params:
  TIER: weekly
  VOLUMES: |
    hermes_agent_data hermes-agent
---

Weekly tar of hermes_agent_data volume (retained 28 days).

Copy to services/automation/backup/cron/ and restart automation-backup to activate.
