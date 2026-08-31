---
cron: "30 3 * * 0"
routine: volume-backup
TIER: weekly
VOLUMES: |
  nocodb_data nocodb
---

Weekly tar of nocodb_data volume (retained 28 days).

Copy to services/decree/decree-backup/cron/ and restart decree-backup to activate.
