---
sidebar_position: 3
---

# rclone

Configures rclone for remote file storage access inside Decree. Supports any rclone-compatible backend: Nextcloud, Dropbox, Google Drive, S3, and more.

## Setup

```bash
./existential.sh run rclone
```

Opens an interactive rclone config session inside the `existential-adhoc` container — no host rclone install needed. Add as many remotes as you need and choose `q` when done.

Config is saved to `automation/secrets/rclone/rclone.conf` and loaded by the container at runtime.

:::note[The `nextcloud` remote configures itself]
If Nextcloud is enabled, a `nextcloud` remote (WebDAV, using the already-rendered admin
credentials) is set up for you automatically by the `nextcloud-rclone-remote` migration —
it's what `file_processor` downloads through for every file event. No need to add it here unless you're pointing it somewhere else.
:::

## Backups

Every backup runs in one daemon, `automation-backup`, which mounts `volumes/` and holds every
service's database credentials, so adding a service to the schedule is one cron file. Databases
are dumped (`pg_dump`, `mysqldump`, `mongodump`), volumes tarred and SQLite copied with
`.backup`, then sent with rclone. Nightly copies are kept 7 days, weekly ones 28.

1. Say where they go: `./existential.sh run rclone`, then name the destination when it asks.
   That writes `EXIST_BACKUP_RCLONE_REMOTE`; nothing is backed up until it is set.
2. Copy a cron per service you enabled, from `services/automation/backup/cron.example/` into
   `services/automation/backup/cron/`: `workspace-volume-backup-nightly.md` first, then each
   `<service>-db-backup-nightly.md` or `<service>-volume-backup-nightly.md`. Each has a
   `-weekly.md` twin for longer retention.
3. Prove it before you need it: copy the active crons into
   `services/automation/backup/inbox/` to run them once now, check
   `docker exec automation-backup decree status`, and look for the files on the remote.
4. Restore: `./existential.sh run backup-restore`.

They live here and not in `automation` because this daemon calls no model: it can hold master
credentials and mount every volume, where a container that puts what it reads in front of a
model must not.
