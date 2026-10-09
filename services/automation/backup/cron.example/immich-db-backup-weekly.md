---
cron: "0 3 * * SUN"
machine: db_backup
params:
  TIER: weekly
  TARGETS: |
    postgres immich-postgres DB_USERNAME DB_PASSWORD
---

Weekly dump of immich-postgres (retained 28 days).

Copy to services/automation/backup/cron/ and restart automation-backup to activate.
