---
cron: "30 3 * * 0"
routine: volume-backup
TIER: weekly
VOLUMES: |
  lowcoder_data   lowcoder-api-service
  lowcoder_assets lowcoder-api-service,lowcoder-frontend
---

Weekly tar of lowcoder volumes (retained 28 days).

Copy to decree/cron/ to activate.
