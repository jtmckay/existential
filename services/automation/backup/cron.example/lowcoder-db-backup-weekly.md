---
cron: "0 3 * * SUN"
machine: db_backup
params:
  TIER: weekly
  TARGETS: |
    mongo lowcoder-mongodb LOWCODER_MONGO_ROOT_USERNAME LOWCODER_MONGO_ROOT_PASSWORD
---

Weekly dump of lowcoder-mongodb (retained 28 days).

Copy to services/automation/backup/cron/ and restart automation-backup to activate.
