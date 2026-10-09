---
cron: "0 4 * * SUN"
machine: volume_backup
params:
  TIER: weekly
  VOLUMES: |
    openviking_data openviking
---

Weekly tar of openviking_data volume (retained 28 days).

Copy to services/automation/backup/cron/ and restart automation-backup to activate.
