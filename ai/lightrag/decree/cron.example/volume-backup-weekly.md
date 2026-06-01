---
cron: "30 3 * * 0"
routine: volume-backup
TIER: weekly
VOLUMES: |
  lightrag_rag_storage_data lightrag
---

Weekly tar of lightrag_rag_storage_data volume (retained 28 days).

Copy to decree/cron/ to activate.
