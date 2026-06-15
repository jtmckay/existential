---
cron: "0 3 * * 0"
routine: db-backup
TIER: weekly
TARGETS: |
  mongo lowcoder-mongodb LOWCODER_MONGO_ROOT_USERNAME LOWCODER_MONGO_ROOT_PASSWORD
---

Weekly dump of lowcoder-mongodb (retained 28 days).

Copy to decree/cron/ to activate.
