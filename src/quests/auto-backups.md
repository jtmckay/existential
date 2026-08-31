---
name: Automated Backups
tagline: Nightly database and volume backups from the decree-backup daemon
e2e: false
services:
  - var: EXIST_IS_SERVICES_DECREE
    label: Decree (runs the backups)
  - var: EXIST_IS_SERVICES_MEALIE
    label: Mealie
  - var: EXIST_IS_SERVICES_NOCODB
    label: NocoDB
  - var: EXIST_IS_SERVICES_LOWCODER
    label: Lowcoder
  - var: EXIST_IS_SERVICES_ACTUAL_BUDGET
    label: Actual Budget
  - var: EXIST_IS_SERVICES_APPSMITH
    label: Appsmith
  - var: EXIST_IS_NAS_NEXTCLOUD
    label: Nextcloud
  - var: EXIST_IS_AI_HERMES
    label: Hermes
  - var: EXIST_IS_HOSTING_PORTAINER
    label: Portainer
copies:
  - src: services/decree/decree-backup/cron.example/mealie-db-backup-nightly.md
    dst: services/decree/decree-backup/cron/
    label: "mealie: db-backup nightly"
    requires: EXIST_IS_SERVICES_MEALIE
  - src: services/decree/decree-backup/cron.example/mealie-volume-backup-nightly.md
    dst: services/decree/decree-backup/cron/
    label: "mealie: volume-backup nightly"
    requires: EXIST_IS_SERVICES_MEALIE
  - src: services/decree/decree-backup/cron.example/nocodb-db-backup-nightly.md
    dst: services/decree/decree-backup/cron/
    label: "nocodb: db-backup nightly"
    requires: EXIST_IS_SERVICES_NOCODB
  - src: services/decree/decree-backup/cron.example/nocodb-volume-backup-nightly.md
    dst: services/decree/decree-backup/cron/
    label: "nocodb: volume-backup nightly"
    requires: EXIST_IS_SERVICES_NOCODB
  - src: services/decree/decree-backup/cron.example/lowcoder-db-backup-nightly.md
    dst: services/decree/decree-backup/cron/
    label: "lowcoder: db-backup nightly"
    requires: EXIST_IS_SERVICES_LOWCODER
  - src: services/decree/decree-backup/cron.example/lowcoder-volume-backup-nightly.md
    dst: services/decree/decree-backup/cron/
    label: "lowcoder: volume-backup nightly"
    requires: EXIST_IS_SERVICES_LOWCODER
  - src: services/decree/decree-backup/cron.example/actual-budget-volume-backup-nightly.md
    dst: services/decree/decree-backup/cron/
    label: "actual-budget: volume-backup nightly"
    requires: EXIST_IS_SERVICES_ACTUAL_BUDGET
  - src: services/decree/decree-backup/cron.example/appsmith-volume-backup-nightly.md
    dst: services/decree/decree-backup/cron/
    label: "appsmith: volume-backup nightly"
    requires: EXIST_IS_SERVICES_APPSMITH
  - src: services/decree/decree-backup/cron.example/nextcloud-db-backup-nightly.md
    dst: services/decree/decree-backup/cron/
    label: "nextcloud: db-backup nightly"
    requires: EXIST_IS_NAS_NEXTCLOUD
  - src: services/decree/decree-backup/cron.example/hermes-volume-backup-nightly.md
    dst: services/decree/decree-backup/cron/
    label: "hermes: volume-backup nightly"
    requires: EXIST_IS_AI_HERMES
---

Activates nightly backup crons for every enabled service that has one.
They all run in one daemon, decree-backup, which mounts volumes/ and holds
every service's DB credentials — so adding a service to this list is one
cron file, not a new sidecar.

Backups are sent to the rclone remote configured in EXIST_BACKUP_RCLONE_REMOTE.
Run backup-config if not yet set up:
  ./existential.sh run backup-config

What gets backed up (nightly, kept for 7 days):
  - Databases (postgres/mariadb/mongo): pg_dump / mysqldump / mongodump → rclone
  - Volumes: tar.gz → rclone

Weekly backups (kept 28 days) sit alongside them — copy the *-weekly.md
files if you want longer-lived snapshots:
  cp services/decree/decree-backup/cron.example/<name>-weekly.md \
     services/decree/decree-backup/cron/
  docker compose restart decree-backup

Manual trigger (for any service):
  docker exec decree-backup decree run db-backup
  docker exec decree-backup decree run volume-backup

Restore:
  ./existential.sh run backup-restore
