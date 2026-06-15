---
cron: "30 3 * * 0"
routine: volume-backup
TIER: weekly
VOLUMES: |
  actual_budget_data actual-budget
---

Weekly tar of actual_budget_data volume (retained 28 days).

Copy to decree/cron/ to activate.
