---
cron: "30 3 * * 0"
routine: volume-backup
TIER: weekly
VOLUMES: |
  vikunja_data vikunja
---

Weekly tar of vikunja_data volume (retained 28 days).

Copy to decree/cron/ to activate.
