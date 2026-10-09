---
cron: "0 3 * * SUN"
machine: db_backup
params:
  TIER: weekly
  TARGETS: |
    mariadb nextcloud-db _LITERAL_root NEXTCLOUD_ROOT_PASSWORD
---

Weekly dump of nextcloud-db (retained 28 days).

Copy to services/automation/backup/cron/ and restart automation-backup to activate.
