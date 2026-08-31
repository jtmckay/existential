---
cron: "30 3 * * 0"
routine: volume-backup
TIER: weekly
VOLUMES: |
  lowcoder_data         lowcoder-api-service
  lowcoder_assets_data  lowcoder-api-service,lowcoder-frontend
---

Weekly tar of lowcoder volumes (retained 28 days).

Copy to services/decree/decree-backup/cron/ and restart decree-backup to activate.
