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
  (see [Getting Started](../getting-started#syncing-with-a-nas-or-a-nextcloud-optional)).
- **notes-pull**: rsync an external notes folder into `workspace/notes/`.

It mounts `volumes/` wholesale, the repo read-only and the master `.env`, which is why it is a
separate container from `automation`: nothing here puts what it reads in front of a model.

## Turning it on

```bash
sed -i 's/^EXIST_IS_SERVICES_AUTOMATION_BACKUP=false/EXIST_IS_SERVICES_AUTOMATION_BACKUP=true/' .env.shared
./existential.sh
docker compose up -d
```

The first run activates triage, clean-runs and workspace-sync. A backup is one more cron file:
copy it from `services/automation-backup/cron.example/` into `services/automation-backup/cron/`.
Restore with `./existential.sh run backup-restore`.

```bash
docker exec automation-backup decree status --cron   # each cron file and when it fires next
```
