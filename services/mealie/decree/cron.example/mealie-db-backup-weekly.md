---
cron: "0 3 * * 0"
routine: db-backup
TIER: weekly
TARGETS: |
  postgres mealie-postgres MEALIE_POSTGRES_USER MEALIE_POSTGRES_PASSWORD
---

Weekly dump of mealie-postgres (retained 28 days).

Copy to decree/cron/ to activate.
