---
cron: "0 4 * * 0"
routine: volume-backup
TIER: weekly
VOLUMES: |
  openviking_data openviking
---

Weekly tar of openviking_data volume (retained 28 days).

Copy to services/decree/decree-backup/cron/ and restart decree-backup to activate.
