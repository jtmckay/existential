---
cron: "0 3 * * 0"
routine: db-backup
TIER: weekly
TARGETS: |
  postgres immich-postgres DB_USERNAME DB_PASSWORD
---

Weekly dump of immich-postgres (retained 28 days).

Copy to services/decree/decree-backup/cron/ and restart decree-backup to activate.
