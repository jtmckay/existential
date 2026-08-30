---
name: NAS Storage
tagline: Mount NFS on the host so persistent data bind-mounts from your NAS
e2e: false
e2e_skip: Requires an external NAS/NFS server
services: []
---

Existential never uses Docker-managed volumes. Every service's persistent
data is a host bind mount under <repo>/volumes/<name>. This gives you
visible, host-owned, inspectable data.

Point it at a NAS and the volumes that are safe to put there move to it.
Only those: each service declares its volumes in an x-exist-volumes block,
and just the ones marked `nfs: true` (bulk user files — Nextcloud, MinIO,
media) relocate. Anything holding a database stays on local disk no matter
what, because NFS corrupts an embedded DB's locking. You get redundancy and
snapshots for the data that benefits, and no silent corruption for the rest.

Any NFS-capable NAS works — TrueNAS is a common self-hosted choice.
Docs: https://existential.company/docs/storage

Setup:
  1. On your NAS, create an NFS export (dataset/share) and record the server
     IP and base path. You do not need to pre-create the per-volume
     subdirectories — ./existential.sh makes the ones your enabled services
     need, once the export is mounted below.

  2. Mount that export on THIS host (Docker no longer mounts NFS itself).
     One-off:
         sudo mkdir -p /mnt/nas
         sudo mount -t nfs <nas-ip>:<base-path> /mnt/nas
     Persist it via /etc/fstab or autofs so it survives reboots, e.g.:
         <nas-ip>:<base-path>  /mnt/nas  nfs  rw,soft,nfsvers=4  0  0

  3. Edit .env.shared and set:
         EXIST_NFS_HOST_MOUNT=/mnt/nas             # the host mountpoint above
         EXIST_NFS_SERVER_ADDRESS=<your-nas-ip>    # documentation only
         EXIST_NFS_BASE_PATH=<nfs-export-base-path># documentation only

  4. Re-render so the generated compose binds persistent volumes to the mount:
         ./existential.sh reset && ./existential.sh
     Reset archives every rendered file to archive/<timestamp>/ first, so
     nothing is lost — .env files included, which it moves rather than
     overwrites. Your volumes are never touched.

If EXIST_NFS_HOST_MOUNT is blank, all data stays under <repo>/volumes/.
Setting EXIST_NFS_SERVER_ADDRESS without EXIST_NFS_HOST_MOUNT is a hard
error (it refuses to silently write NFS data to local disk). You can skip
this quest and add NFS later at any time.
