---
sidebar_position: 1
---

# Storage Overview

Use what you need. For example, Google Drive for files instead of TrueNAS and Nextcloud.

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

Data lives under `<repo>/volumes/<name>`. With a NAS, the volumes marked `nfs: true` (bulk
files: Nextcloud, photos, media) can live on it instead. Databases never do: NFS breaks their
locking. Any NFS NAS works, and Docker Compose mounts the export itself, so there is nothing to
set up on this host.

1. On the NAS, export a share over NFS to this host, and make a folder on it for each volume,
   owned by `EXIST_PUID:EXIST_PGID` (your user's uid:gid; `id -u`, `id -g`). Nothing in the
   stack creates or changes anything on the NAS.
2. Run `./existential.sh`. The first run with a NAS volume enabled asks for the NAS address
   (`EXIST_NFS_ADDRESS`; Enter is `none`, which keeps everything local and is not asked again),
   then for each volume's folder on the export (`EXIST_NFS_PATH_<VOLUME>`, e.g.
   `EXIST_NFS_PATH_NEXTCLOUD_DATA`). `local` keeps that one volume under `<repo>/volumes/`.
   Each answer is written to `.env.shared` and never asked again; turning on another service
   asks for its volumes, and setting the address later asks for every enabled one.
3. `./existential.sh` prints the address and the folders the stack will mount. Then
   `docker compose up -d`.

Without a terminal nothing is asked, and a run with an address but a missing path stops and
names the key to set. A folder that is missing or unreachable stops the container that mounts
it; it is never replaced by a local directory.

### Changing a path

Edit its `EXIST_NFS_PATH_<VOLUME>` in `.env.shared` and run `./existential.sh`. Compose refuses
to reuse an NFS volume whose definition changed, so remove the old definition and recreate:

```bash
docker compose down <service>
docker volume rm <repo-folder>_<volume>   # the definition only; the data on the NAS is untouched
docker compose up -d
```

`docker volume ls` shows the volume's full name.

Moving data between folders, or from `<repo>/volumes/` to the NAS, is yours to do.
