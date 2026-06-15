---
cron: "0 3 * * 0"
routine: db-backup
TIER: weekly
TARGETS: |
  mariadb nextcloud-db _LITERAL_root NEXTCLOUD_ROOT_PASSWORD
---

Weekly dump of nextcloud-db (retained 28 days).

Copy to decree/cron/ to activate.
