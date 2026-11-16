---
machine: plugin
automation: backup-uptime-kuma
project: backup
name: Back up Uptime Kuma
tagline: Uptime Kuma, backed up nightly and weekly to your rclone remote
docs: /docs/decree/automation-backup
services:
  - EXIST_IS_SERVICES_AUTOMATION_BACKUP
  - EXIST_IS_HOSTING_UPTIME_KUMA
needs:
  - sqlite_backup
cron:
  uptime-kuma-sqlite-backup-nightly: |
    ---
    cron: "0 3 * * *"
    machine: sqlite_backup
    params:
      TIER: nightly
      TARGETS: |
        kuma uptime_kuma_data/kuma.db
    ---

    Dump uptime-kuma's SQLite database nightly (transaction-consistent, via `sqlite3 .dump`)
    and rclone the gzipped SQL to ${EXIST_BACKUP_RCLONE_REMOTE}/nightly/sqlite/kuma/.
    Files older than 7 days are pruned at the end of the run.

    This is the only backup uptime-kuma has: v2 removed Settings → Backup & Restore, so
    monitors and notifications exist nowhere but kuma.db.
  uptime-kuma-sqlite-backup-weekly: |
    ---
    cron: "0 4 * * SUN"
    machine: sqlite_backup
    params:
      TIER: weekly
      TARGETS: |
        kuma uptime_kuma_data/kuma.db
    ---

    Weekly dump of uptime-kuma's SQLite database to
    ${EXIST_BACKUP_RCLONE_REMOTE}/weekly/sqlite/kuma/ (retained 28 days).

    This is the only backup uptime-kuma has: v2 removed Settings → Backup & Restore, so
    monitors and notifications exist nowhere but kuma.db.
---

Backups go to the rclone remote in EXIST_BACKUP_RCLONE_REMOTE (.env.shared); add it once with
./existential.sh run rclone. Restore with ./existential.sh run backup-restore. For another
schedule, edit the cron files in services/automation-backup/cron/.
