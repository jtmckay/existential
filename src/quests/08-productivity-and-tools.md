---
name: Productivity & Tools
tagline: Tasks, databases, and low-code apps
e2e: true
services:
  - var: EXIST_IS_SERVICES_NOCODB
    label: NocoDB
  - var: EXIST_IS_SERVICES_APPSMITH
    label: Appsmith
  - var: EXIST_IS_SERVICES_LOWCODER
    label: Lowcoder
  - var: EXIST_IS_SERVICES_IT_TOOLS
    label: IT Tools
---

NocoDB, Appsmith and Lowcoder each bundle their own database — nothing here
shares nas/redis or nas/nextcloud. IT Tools is stateless (no backup needed).

Nightly backups (kept 7 days) run in decree-backup once you copy their cron
files in. Copy only the ones for what you enabled:

  mkdir -p services/automation/backup/cron/

  # NocoDB — Postgres + upload volume
  cp services/automation/backup/cron.example/nocodb-db-backup-nightly.md \
     services/automation/backup/cron.example/nocodb-volume-backup-nightly.md \
     services/automation/backup/cron/

  # Appsmith — embedded Mongo/Redis/Postgres live inside its one volume
  cp services/automation/backup/cron.example/appsmith-volume-backup-nightly.md \
     services/automation/backup/cron/

  # Lowcoder — Mongo + its own volume
  cp services/automation/backup/cron.example/lowcoder-db-backup-nightly.md \
     services/automation/backup/cron.example/lowcoder-volume-backup-nightly.md \
     services/automation/backup/cron/

  docker compose restart automation-backup

Weekly backups (kept 28 days) sit alongside the nightly ones — same idea,
copy the matching `-weekly.md` file instead of (or as well as) `-nightly.md`.

Manual trigger:
  printf -- '---\nroutine: db-backup\n---\n' > services/automation/backup/inbox/db-backup.md
  printf -- '---\nroutine: volume-backup\n---\n' > services/automation/backup/inbox/volume-backup.md

Restore:
  ./existential.sh run backup-restore
