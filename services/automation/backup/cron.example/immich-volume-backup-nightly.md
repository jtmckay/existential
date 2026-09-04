---
cron: "30 2 * * *"
routine: volume-backup
TIER: nightly
VOLUMES: |
  immich_library immich-server
---

Tar the immich_library volume (your uploaded photos/videos) nightly and rclone to
${EXIST_BACKUP_RCLONE_REMOTE}/nightly/volumes/immich_library/. Files older than 7
days are pruned at the end of the run.

Only reaches the DEFAULT UPLOAD_LOCATION (./volumes/immich_library) — decree-backup
mounts the repo's volumes/ directory wholesale, so this is a no-op (clean skip, not
a failure) if you pointed UPLOAD_LOCATION at NFS or another host path instead. Back
that up separately.

Copy to services/automation/backup/cron/ and restart automation-backup to activate.
