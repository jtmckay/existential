---
cron: "30 3 * * SUN"
machine: volume_backup
params:
  TIER: weekly
  VOLUMES: |
    appsmith_data appsmith
---

Weekly tar of appsmith_data volume (retained 28 days).

Copy to services/automation/backup/cron/ and restart automation-backup to activate.
