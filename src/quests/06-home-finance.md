---
name: Home Finance
tagline: Track spending and plan meals without a subscription
e2e: true
services:
  - var: EXIST_IS_SERVICES_ACTUAL_BUDGET
    label: Actual Budget
  - var: EXIST_IS_SERVICES_MEALIE
    label: Mealie
---

Actual Budget's whole database lives in one volume; Mealie is a Postgres
database plus an uploads volume. Both back up through decree-backup — copy
only the crons for what you enabled:

  mkdir -p services/automation/backup/cron/

  # Actual Budget — nightly volume backup
  cp services/automation/backup/cron.example/actual-budget-volume-backup-nightly.md \
     services/automation/backup/cron/

  # Mealie — nightly DB dump + volume backup
  cp services/automation/backup/cron.example/mealie-db-backup-nightly.md \
     services/automation/backup/cron.example/mealie-volume-backup-nightly.md \
     services/automation/backup/cron/

  docker compose restart automation-backup

Weekly backups (kept 28 days, vs. 7 for nightly) sit alongside these — copy
the matching `-weekly.md` file the same way if you want longer retention.

Actual Budget needs one more one-time step the first time you use it: open
https://actual-budget.<domain> and create a budget file, or run
`./existential.sh run actual-budget setup` to bootstrap it non-interactively.

Manual trigger:
  printf -- '---\nroutine: db-backup\n---\n' > services/automation/backup/inbox/db-backup.md
  printf -- '---\nroutine: volume-backup\n---\n' > services/automation/backup/inbox/volume-backup.md
