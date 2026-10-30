---
cron: "30 2 * * *"
machine: volume_backup
params:
  TIER: nightly
  VOLUMES: |
    immich_data immich-server
---

Tar the immich_data volume (your uploaded photos/videos) nightly and rclone to
${EXIST_BACKUP_RCLONE_REMOTE}/nightly/volumes/immich_data/. Files older than 7
days are pruned at the end of the run.

immich_data is a declared volume under volumes/, which automation-backup mounts
wholesale. On the NAS (EXIST_NFS_PATH_IMMICH_DATA) it is not under volumes/ and
this finds nothing: back it up on the NAS.

Copy to services/automation-backup/cron/ and restart automation-backup to activate.
