---
cron: "0 3 * * SUN"
machine: db_backup
params:
  TIER: weekly
  TARGETS: |
    postgres mealie-postgres MEALIE_POSTGRES_USER MEALIE_POSTGRES_PASSWORD
---

Weekly dump of mealie-postgres (retained 28 days).

Copy to services/automation/backup/cron/ and restart automation-backup to activate.
