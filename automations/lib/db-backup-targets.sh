#!/usr/bin/env bash
# DB backup targets registry — sourced by routines/db-backup.sh.
#
# Each backup_register call wires one database into the backup routine.
# When a new DB-using service is added to the stack, append a line here.
#
# Arguments:
#   1. engine    — postgres | mariadb | mongo
#   2. container — container_name on the `exist` Docker network
#   3. user_env  — name of the env var holding the admin/superuser
#   4. pass_env  — name of the env var holding that user's password
#
# Both env vars are looked up from the master .env (sourced by db-backup.sh).
# An entry is silently skipped at runtime if its container is not reachable —
# disabled services don't cause the routine to fail.

BACKUP_TARGETS=()

backup_register() {
    BACKUP_TARGETS+=("$1|$2|$3|$4")
}

# Postgres
backup_register postgres mealie-postgres     MEALIE_POSTGRES_USER       MEALIE_POSTGRES_PASSWORD
backup_register postgres nocodb-postgres     NOCODB_POSTGRES_USER       NOCODB_POSTGRES_PASSWORD
backup_register postgres vikunja-db          VIKUNJA_DATABASE_USER      VIKUNJA_DATABASE_PASSWORD
backup_register postgres librechat-vectordb  _LITERAL_librechat         LIBRECHAT_PG_PASSWORD

# MariaDB
backup_register mariadb  nextcloud-db        _LITERAL_root              NEXTCLOUD_ROOT_PASSWORD

# MongoDB
backup_register mongo    lowcoder-mongodb    LOWCODER_MONGO_ROOT_USERNAME  LOWCODER_MONGO_ROOT_PASSWORD
