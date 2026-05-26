---
cron: "0 2 * * *"
routine: db-backup
TIER: nightly
TARGETS: |
  postgres mealie-postgres     MEALIE_POSTGRES_USER         MEALIE_POSTGRES_PASSWORD
  postgres nocodb-postgres     NOCODB_POSTGRES_USER         NOCODB_POSTGRES_PASSWORD
  postgres vikunja-db          VIKUNJA_DATABASE_USER        VIKUNJA_DATABASE_PASSWORD
  postgres librechat-vectordb  _LITERAL_librechat           LIBRECHAT_PG_PASSWORD
  mariadb  nextcloud-db        _LITERAL_root                NEXTCLOUD_ROOT_PASSWORD
  mongo    lowcoder-mongodb    LOWCODER_MONGO_ROOT_USERNAME LOWCODER_MONGO_ROOT_PASSWORD
---

Dump every reachable database (Postgres / MariaDB / Mongo) and rclone
them to `${EXIST_BACKUP_RCLONE_REMOTE}/nightly/<container>/`. Files
older than 7 days are pruned at the end of the run.

`TARGETS` format: one entry per line, whitespace-separated:
  `<engine> <container> <USER_ENV_VAR> <PASS_ENV_VAR>`

The two env-var names are looked up against the master `.env` mounted at
`/repo/.env`. Use the `_LITERAL_<value>` prefix when the username is a
fixed string rather than an env var (e.g. `_LITERAL_root`).

An entry whose container isn't reachable on the `exist` network is
silently skipped — disabled services don't cause the routine to fail.

Copy this file into `services/decree/decree-backup/cron/` to activate.
