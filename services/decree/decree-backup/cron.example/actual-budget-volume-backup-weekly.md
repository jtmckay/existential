---
cron: "30 3 * * 0"
routine: volume-backup
TIER: weekly
VOLUMES: |
  actual_budget_data actual-budget
---

Weekly tar of actual_budget_data volume (retained 28 days).

Copy to services/decree/decree-backup/cron/ and restart decree-backup to activate.
