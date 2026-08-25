---
cron: "0 3 * * 0"
routine: db-backup
TIER: weekly
TARGETS: |
  postgres vikunja-db VIKUNJA_DATABASE_USER VIKUNJA_DATABASE_PASSWORD
---

Weekly dump of vikunja-db (retained 28 days).

Copy to decree/cron/ to activate.
