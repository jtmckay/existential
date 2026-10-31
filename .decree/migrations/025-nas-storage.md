---
machine: develop
---
# NAS storage: Compose mounts the export, you choose every path

## Overview

Bulk files (Nextcloud, photos, media) belong on a NAS, and most people who have one already
have shares and folders on it. The stack should mount what is there, where the person says,
and never guess: a volume that cannot reach its NAS folder must stop its container rather than
quietly write to local disk, and nothing the stack runs should create or change anything on
the NAS. Compose mounts NFS itself, so nothing about the host (fstab, autofs, mount order at
boot) is part of the setup.

## Outcome

- **The NAS address is one key, asked once.** `EXIST_NFS_ADDRESS` ships blank in
  `.env.exist.shared`, blank meaning not yet asked. The first run that has an enabled service
  declaring an `nfs: true` volume asks for it, naming that service. Enter answers `none`: no
  NAS, every volume stays under `<repo>/volumes/`, and it is not asked again.
- **Every NAS volume gets its path from the person.** For each `nfs: true` volume of an
  enabled service, `EXIST_NFS_PATH_<VOLUME>` in `.env.shared` (`EXIST_NFS_PATH_NEXTCLOUD_DATA`)
  is that volume's folder on the export. A run asks for each one that is missing while
  `EXIST_NFS_ADDRESS` is an address, so turning on a service asks for its volumes, and setting
  the address later asks for every enabled service's volumes at once. The question shows the
  trailing comment on the volume's `x-exist-volumes` line, saying what it holds. Nothing is suggested: Enter answers `none`, which
  keeps that one volume under `<repo>/volumes/`. Each answer is appended to `.env.shared`
  with a one-line comment, and never asked again.
- **Compose mounts the NAS.** A volume with a path is a top-level `local` volume in the
  generated `docker-compose.yml`, with NFS `driver_opts` (`type: nfs`,
  `o: addr=<address>,rw,nfsvers=4`, `device: ":<path>"`), mounted `nocopy`. Every other volume
  is a bind under `<repo>/volumes/`, and the top-level `volumes:` holds only the NFS ones.
  Nothing on the host mounts the export, and no doc has an fstab, autofs or `mount` step.
- **Nothing writes to the NAS but the services.** No part of the stack creates, chowns or
  writes a folder on the export. The person makes each folder, owned by
  `EXIST_PUID:EXIST_PGID`, and `./existential.sh` prints the address and paths the enabled
  services will mount. A missing or unreachable folder stops the container that mounts it; it
  is never replaced by a local directory.
- **A database is never on the NAS.** A `db: true` volume is never asked for a path, and
  `validate conventions` rejects `db: true` together with `nfs: true`.
- **Changing a path is deliberate.** Compose refuses an NFS volume whose definition changed
  until it is recreated; the Storage page gives the commands. Data on the NAS is never touched.
- **Existing files reach Nextcloud as External storage.** The Nextcloud page says that
  `nextcloud_data` holds Nextcloud's own layout, so a share of existing files is not given as
  its path, and how to mount such a share as External storage instead.
- The Storage page, the configuration reference, the Nextcloud and Immich pages,
  `.claude/reference/volumes.md`, `.claude/reference/templates.md` and CLAUDE.md describe
  this. `EXIST_NFS_HOST_MOUNT`, `EXIST_NFS_SERVER_ADDRESS` and `EXIST_NFS_BASE_PATH` do not
  exist.

## Constraints

- Without a terminal nothing is asked: a blank address stays blank, and a generated
  `docker-compose.yml` with an address but a missing path fails, naming the key to set.
- An install with no `nfs: true` service enabled is asked nothing new.
- An existing `.env.shared` that still holds `EXIST_NFS_HOST_MOUNT` keeps working: the key is
  ignored, never an error.

## Acceptance Criteria

- **Given** `EXIST_NFS_ADDRESS=10.0.0.5`, `EXIST_NFS_PATH_NEXTCLOUD_DATA=/tank/cloud` and
  nextcloud enabled
  **When** `docker-compose.yml` is generated
  **Then** `nextcloud_data` is a top-level volume with `type: nfs`, `addr=10.0.0.5` and
  `device: ":/tank/cloud"`, and `nextcloud_sql_data` is a bind under `volumes/`
- **Given** `EXIST_NFS_SHARE_NEXTCLOUD=none`
  **When** `docker-compose.yml` is generated
  **Then** `nextcloud_share` is a bind under `volumes/`
- **Given** `EXIST_NFS_ADDRESS=none` or blank
  **When** `docker-compose.yml` is generated
  **Then** it has no top-level `volumes:` block
- **Given** an address and nextcloud enabled with no `EXIST_NFS_PATH_NEXTCLOUD_DATA`, and no
  terminal
  **When** `./existential.sh` runs
  **Then** it fails naming `EXIST_NFS_PATH_NEXTCLOUD_DATA`
- **Given** the repo
  **When** `git grep` runs for `EXIST_NFS_HOST_MOUNT`, `EXIST_NFS_SERVER_ADDRESS` or
  `EXIST_NFS_BASE_PATH` outside `graveyard/`, `.decree/` and this file
  **Then** nothing is found
