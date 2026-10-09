---
cron: "0 3 * * SUN"
machine: db_backup
params:
  TIER: weekly
  TARGETS: |
    postgres honcho-postgres _LITERAL_honcho HONCHO_POSTGRES_PASSWORD
---

Weekly dump of honcho-postgres (retained 28 days).

Copy to services/automation/backup/cron/ and restart automation-backup to activate.
