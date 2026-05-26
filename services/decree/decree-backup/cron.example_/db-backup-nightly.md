---
cron: "0 2 * * *"
routine: db-backup
TIER: nightly
---

Dump every reachable database (Postgres / MariaDB / Mongo) and rclone
them to `${EXIST_BACKUP_RCLONE_REMOTE}/nightly/<container>/`. Files
older than 7 days are pruned at the end of the run.

Targets are registered in `automations/lib/db-backup-targets.sh`.
Destination is configured via `./existential.sh setup backup`.

Copy this file into `services/decree/decree-backup/cron/` to activate.
