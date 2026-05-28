---
cron: "30 3 * * 0"
routine: volume-backup
TIER: weekly
VOLUMES: |
  nocodb_data nocodb
---

Weekly tar of nocodb_data volume (retained 28 days).

Copy to decree/cron/ to activate.
