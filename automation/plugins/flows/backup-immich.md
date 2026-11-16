---
machine: plugin
automation: backup-immich
project: backup
name: Back up Immich
tagline: Immich, backed up nightly and weekly to your rclone remote
docs: /docs/decree/automation-backup
services:
  - EXIST_IS_SERVICES_AUTOMATION_BACKUP
  - EXIST_IS_SERVICES_IMMICH
needs:
  - db_backup
  - volume_backup
cron:
  immich-db-backup-nightly: |
    ---
    cron: "0 2 * * *"
    machine: db_backup
    params:
      TIER: nightly
      TARGETS: |
        postgres immich-postgres DB_USERNAME DB_PASSWORD
    ---

    Dump immich-postgres nightly and rclone to ${EXIST_BACKUP_RCLONE_REMOTE}/nightly/immich-postgres/.
    Files older than 7 days are pruned at the end of the run.

    DB_USERNAME/DB_PASSWORD are immich's own (unprefixed — `.env.exist` is
    convention-exempt: upstream-env) and land in decree-backup's environment via
    the master `.env`, same as every other service here.
  immich-db-backup-weekly: |
    ---
    cron: "0 3 * * SUN"
    machine: db_backup
    params:
      TIER: weekly
      TARGETS: |
        postgres immich-postgres DB_USERNAME DB_PASSWORD
    ---

    Weekly dump of immich-postgres (retained 28 days).
  immich-volume-backup-nightly: |
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
  immich-volume-backup-weekly: |
    ---
    cron: "30 3 * * SUN"
    machine: volume_backup
    params:
      TIER: weekly
      VOLUMES: |
        immich_data immich-server
    ---

    Weekly tar of the immich_data volume (retained 28 days). Same DEFAULT-path
    caveat as the nightly cron — see that file.
---

Backups go to the rclone remote in EXIST_BACKUP_RCLONE_REMOTE (.env.shared); add it once with
./existential.sh run rclone. Restore with ./existential.sh run backup-restore. For another
schedule, edit the cron files in services/automation-backup/cron/.
