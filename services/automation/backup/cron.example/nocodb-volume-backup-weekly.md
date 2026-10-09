---
cron: "30 3 * * SUN"
machine: volume_backup
params:
  TIER: weekly
  VOLUMES: |
    nocodb_data nocodb
---

Weekly tar of nocodb_data volume (retained 28 days).

Copy to services/automation/backup/cron/ and restart automation-backup to activate.
