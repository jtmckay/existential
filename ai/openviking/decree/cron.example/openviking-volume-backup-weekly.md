---
cron: "0 4 * * 0"
routine: volume-backup
TIER: weekly
VOLUMES: |
  openviking_data openviking
---

Weekly tar of openviking_data volume (retained 28 days).

Copy to decree/cron/ to activate.
