---
cron: "0 3 * * 0"
routine: db-backup
TIER: weekly
TARGETS: |
  mariadb nextcloud-db _LITERAL_root NEXTCLOUD_ROOT_PASSWORD
---

Weekly dump of nextcloud-db (retained 28 days).

Copy to services/decree/decree-backup/cron/ and restart decree-backup to activate.
