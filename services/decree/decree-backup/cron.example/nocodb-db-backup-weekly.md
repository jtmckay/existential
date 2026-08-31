---
cron: "0 3 * * 0"
routine: db-backup
TIER: weekly
TARGETS: |
  postgres nocodb-postgres NOCODB_POSTGRES_USER NOCODB_POSTGRES_PASSWORD
---

Weekly dump of nocodb-postgres (retained 28 days).

Copy to services/decree/decree-backup/cron/ and restart decree-backup to activate.
