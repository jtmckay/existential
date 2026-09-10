---
cron: "30 2 * * *"
routine: volume-backup
TIER: nightly
VOLUMES: |
  immich_data immich-server
---

Tar the immich_data volume (your uploaded photos/videos) nightly and rclone to
${EXIST_BACKUP_RCLONE_REMOTE}/nightly/volumes/immich_data/. Files older than 7
days are pruned at the end of the run.

immich_data is a declared volume under volumes/, which automation-backup mounts
wholesale, so this reaches it wherever generate-compose.ts placed it — including
the NFS host mount, since the volume is nfs: true. Back
that up separately.

Copy to services/automation/backup/cron/ and restart automation-backup to activate.
