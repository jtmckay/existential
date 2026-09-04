---
cron: "30 3 * * 0"
routine: volume-backup
TIER: weekly
VOLUMES: |
  mealie_data mealie
---

Weekly tar of mealie_data volume (retained 28 days).

Copy to services/automation/backup/cron/ and restart automation-backup to activate.
