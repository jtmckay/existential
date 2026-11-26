---
service: services/automation-backup
sidebar_position: 3
---

# Automation Backup

`automation-backup` is the second decree daemon. It is **off by default**: backups are not part
of Core. It holds what needs bulk access and makes no AI call:

- **Backups**: volume tarballs and database dumps, one cron file each.
- **triage**: runs every enabled service's own test on a schedule and notifies you when one
  breaks or recovers.
- **workspace-sync**: two-way sync of `workspace/` with a NAS or Nextcloud folder, every minute
  (see [Getting Started](../getting-started.md#syncing-with-a-nas-or-a-nextcloud-optional)).
- **notes-pull**: rsync an external notes folder into `workspace/notes/`.

It mounts `volumes/` wholesale, the repo read-only and the master `.env`, which is why it is a
separate container from `automation`: nothing here puts what it reads in front of a model.

## Turning it on

```bash
sed -i 's/^EXIST_IS_SERVICES_AUTOMATION_BACKUP=false/EXIST_IS_SERVICES_AUTOMATION_BACKUP=true/' .env.shared
./existential.sh
docker compose up -d
```

Enabling it schedules only the pruning of its finished runs. Everything else it can do is a
plugin you turn on: `triage`, `workspace_sync`, `notes_pull`, and the backups
(`./existential.sh plugin on volume_backup db_backup sqlite_backup`, each listing every service
it knows). A plugin's crons land in `services/automation-backup/machines/<plugin>/cron/`, where
you can change a schedule, or delete a service's line.
Restore with `./existential.sh run backup-restore`.

```bash
docker exec automation-backup decree status --cron   # each cron file and when it fires next
```
