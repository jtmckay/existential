---
name: Automated Backups
tagline: Nightly database and volume backups from the decree-backup daemon
e2e: false
services:
  - var: EXIST_IS_SERVICES_AUTOMATION
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

Copy only the crons for services you actually enabled:

  mkdir -p services/automation/backup/cron/

  # Mealie — Postgres + uploads volume
  cp services/automation/backup/cron.example/mealie-db-backup-nightly.md \
     services/automation/backup/cron.example/mealie-volume-backup-nightly.md \
     services/automation/backup/cron/

  # NocoDB — Postgres + uploads volume
  cp services/automation/backup/cron.example/nocodb-db-backup-nightly.md \
     services/automation/backup/cron.example/nocodb-volume-backup-nightly.md \
     services/automation/backup/cron/

  # Lowcoder — Mongo + its own volume
  cp services/automation/backup/cron.example/lowcoder-db-backup-nightly.md \
     services/automation/backup/cron.example/lowcoder-volume-backup-nightly.md \
     services/automation/backup/cron/

  # Actual Budget — whole DB lives in one volume, no separate db-backup
  cp services/automation/backup/cron.example/actual-budget-volume-backup-nightly.md \
     services/automation/backup/cron/

  # Appsmith — embedded Mongo/Redis/Postgres live inside its one volume
  cp services/automation/backup/cron.example/appsmith-volume-backup-nightly.md \
     services/automation/backup/cron/

  # Nextcloud — DB only (files already live on your NFS/nas volume separately)
  cp services/automation/backup/cron.example/nextcloud-db-backup-nightly.md \
     services/automation/backup/cron/

  # Hermes — config + skills volume
  cp services/automation/backup/cron.example/hermes-volume-backup-nightly.md \
     services/automation/backup/cron/

  docker compose restart automation-backup

Weekly backups (kept 28 days) sit alongside them — copy the *-weekly.md
files if you want longer-lived snapshots:
  cp services/automation/backup/cron.example/<name>-weekly.md \
     services/automation/backup/cron/
  docker compose restart automation-backup

Manual trigger (for any service):
  docker exec automation-backup decree run db-backup
  docker exec automation-backup decree run volume-backup

Restore:
  ./existential.sh run backup-restore
