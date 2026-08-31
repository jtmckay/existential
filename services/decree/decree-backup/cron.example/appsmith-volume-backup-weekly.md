---
cron: "30 3 * * 0"
routine: volume-backup
TIER: weekly
VOLUMES: |
  appsmith_data appsmith
---

Weekly tar of appsmith_data volume (retained 28 days).

Copy to services/decree/decree-backup/cron/ and restart decree-backup to activate.
