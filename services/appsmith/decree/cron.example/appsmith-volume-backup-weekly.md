---
cron: "30 3 * * 0"
routine: volume-backup
TIER: weekly
VOLUMES: |
  appsmith_data appsmith
---

Weekly tar of appsmith_data volume (retained 28 days).

Copy to decree/cron/ to activate.
