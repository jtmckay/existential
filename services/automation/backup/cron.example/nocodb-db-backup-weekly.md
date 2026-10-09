---
cron: "0 3 * * SUN"
machine: db_backup
params:
  TIER: weekly
  TARGETS: |
    postgres nocodb-postgres NOCODB_POSTGRES_USER NOCODB_POSTGRES_PASSWORD
---

Weekly dump of nocodb-postgres (retained 28 days).

Copy to services/automation/backup/cron/ and restart automation-backup to activate.
