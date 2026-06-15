---
cron: "30 3 * * 0"
routine: volume-backup
TIER: weekly
VOLUMES: |
  mealie_data mealie
---

Weekly tar of mealie_data volume (retained 28 days).

Copy to decree/cron/ to activate.
