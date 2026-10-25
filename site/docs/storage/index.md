---
sidebar_position: 1
---

# Storage Overview

Pick and choose components to use. For example: use Google Drive for files and skip TrueNAS and Nextcloud.

## What's Important

- **NFS** — Container persistence
- **Nextcloud** — Desktop and mobile app file sync (image/video upload, etc.), and the file
  events automations react to

## Components

| Service                     | Purpose                | Alternatives                    |
| --------------------------- | ---------------------- | ------------------------------- |
| [Nextcloud](./nextcloud)    | File sharing & sync    | Dropbox, OneDrive, Google Drive |
| [Collabora](./collabora)    | Nextcloud document editor | OnlyOffice                   |
| TrueNAS                     | File redundancy & NFS  | —                               |

## A NAS for the bulk files

Every service's data is a host bind mount under `<repo>/volumes/<name>`, never a Docker-managed
volume. Point the stack at a NAS and the volumes that are safe there move to it, and only those:
each service declares its volumes in an `x-exist-volumes` block, and just the ones marked
`nfs: true` (bulk user files: Nextcloud, media) relocate. Anything holding a database stays on
local disk whatever you set, because NFS corrupts an embedded database's locking. Any NFS-capable
NAS works; TrueNAS is a common self-hosted choice.

1. On the NAS, create an NFS export and note its address and path. The per-volume
   subdirectories are made for you once it is mounted.
2. Mount it on **this host**; Docker never mounts NFS itself:
   ```bash
   sudo mkdir -p /mnt/nas
   sudo mount -t nfs <nas-ip>:<base-path> /mnt/nas
   ```
   and keep it across reboots with an `/etc/fstab` line (or autofs):
   `<nas-ip>:<base-path>  /mnt/nas  nfs  rw,soft,nfsvers=4  0  0`
3. In `.env.shared`, set `EXIST_NFS_HOST_MOUNT=/mnt/nas`.
4. Re-render so the compose file binds those volumes to the mount:
   `./existential.sh reset && ./existential.sh`. Reset archives every rendered file to
   `archive/<timestamp>/` first, `.env` files included, and never touches your volumes.

Leave `EXIST_NFS_HOST_MOUNT` blank and everything stays under `<repo>/volumes/`.
