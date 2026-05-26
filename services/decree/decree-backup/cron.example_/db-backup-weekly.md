---
cron: "0 3 * * 0"
routine: db-backup
TIER: weekly
TARGETS: |
  postgres mealie-postgres     MEALIE_POSTGRES_USER         MEALIE_POSTGRES_PASSWORD
  postgres nocodb-postgres     NOCODB_POSTGRES_USER         NOCODB_POSTGRES_PASSWORD
  postgres vikunja-db          VIKUNJA_DATABASE_USER        VIKUNJA_DATABASE_PASSWORD
  postgres librechat-vectordb  _LITERAL_librechat           LIBRECHAT_PG_PASSWORD
  mariadb  nextcloud-db        _LITERAL_root                NEXTCLOUD_ROOT_PASSWORD
  mongo    lowcoder-mongodb    LOWCODER_MONGO_ROOT_USERNAME LOWCODER_MONGO_ROOT_PASSWORD
---

Weekly counterpart to db-backup-nightly. Same `TARGETS` list, written to
`${EXIST_BACKUP_RCLONE_REMOTE}/weekly/<container>/` with a 28-day
retention window — gives you a longer-horizon recovery point in case a
problem isn't noticed within the nightly window.

If you change the nightly `TARGETS`, change the weekly one to match.

Copy this file into `services/decree/decree-backup/cron/` to activate.
