# Homelab backups

## Why

Losing the photo library twice taught me that a backup I never restored is a hope, not a backup.

## How it runs

Restic snapshots `volumes/` to the NAS every night at 02:00. The repository password lives in the
password manager under "restic-nas".

```bash
restic -r sftp:nas:/backups/homelab backup /srv/existential/volumes --exclude-caches
restic -r sftp:nas:/backups/homelab forget --keep-daily 7 --keep-weekly 5 --prune
```

## Restore drill

Once a quarter, restore one random directory into /tmp and diff it against the live copy.
