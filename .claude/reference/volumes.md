# Volumes

**We never use Docker-managed volumes** — they're opaque and re-init from the image (wrong UID
on NFS). Every volume is a **host bind mount**: visible, inspectable, correctly-owned.

Templates declare bind mounts **directly** — there is no top-level `volumes:` block and no
`materializeBindMounts` rewrite. Consolidation stays minimal: `generate-compose.ts`'s generic
`adjustVolume` only fixes the relative path (prepends the service dir, normalises to repo root)
— `../../<dir>/<name>` → `./<dir>/<name>`, the same handling every bind mount gets, for **any**
top-level dir. The generated `docker-compose.yml` has no `volumes:` block and `docker volume ls`
stays empty; `validate conventions` enforces this (no top-level volumes, no bare named refs).

## Three tiers

Picked by "is this backup-worthy?" and "is it NFS-safe?" Name volumes `<service>_<purpose>_data`.

| Tier | Form in template | NFS? | Backed up? | For |
|---|---|---|---|---|
| **1 — User data** | `- ${EXIST_NFS_HOST_MOUNT:-./volumes}/<name>:/path` | yes | yes (sidecar) | bulk files/blobs/media/attachments — NFS-safe |
| **2 — Live DB** | `- ../../volumes_local/<name>:/path` | **never** | yes — sidecar writes a safe archive into `volumes/<name>_backup/` | postgres, mariadb, mongo, embedded SQLite/bbolt/TSDB worth keeping |
| **3 — Ephemeral** | `- ./<dir>:/path` (in the service dir, gitignored) | no | **no sidecar** | caches, downloaded models, scratch, transient state |

**Decision rule: local-required AND backup-worthy → tier 2; local-required but throwaway → tier
3; NFS-safe and backup-worthy → tier 1.** An embedded database (mmap, `flock`, SQLite WAL —
prometheus TSDB, bbolt, mongo) **must never** be tier 1: NFS corrupts or cripples it.

- **Tier 1** (`${EXIST_NFS_HOST_MOUNT:-./volumes}/<name>`): when a host NFS mount is set,
  `templates.sh` substitutes `${EXIST_NFS_HOST_MOUNT}` in (→ `/mnt/.../<name>`); unset →
  Docker's `:-./volumes` fallback keeps it local. The export is mounted on the **host**
  (fstab/autofs) — Docker no longer mounts NFS itself. `EXIST_NFS_SERVER_ADDRESS` set without
  `EXIST_NFS_HOST_MOUNT` is a hard error in `generate-compose.ts` (won't silently fall back).
- **Tier 2** (`../../volumes_local/<name>`): plain relative path, no NFS token, so it is
  **always** local — `adjustVolume` rewrites it to `./volumes_local/<name>` at repo root. Its
  matching NFS archive dir is tier 1 (`volumes/<name>_backup/`), where the service's
  `*-decree` sidecar drops crash-consistent dumps (dump mechanism is per-service; some are
  still `# TODO: backup sidecar`). No DB worth keeping should be a bare local dir with no
  archive path.
- **Tier 3** (`./<dir>` inside the service folder, gitignored): no archive, no sidecar. If a
  thing isn't worth backing up, it doesn't get a `volumes/` entry or a sidecar tarring it.

## .gitkeep

**Every** bind dir gets a committed `.gitkeep` so it exists on a fresh clone and Docker doesn't
root-create it (wrong owner): tier 1 `volumes/<name>/.gitkeep` (incl. each `<name>_backup`),
tier 2 `volumes_local/<name>/.gitkeep`, and tier 3 `<service>/<dir>/.gitkeep` inside the service
folder. Tier-3 `.gitkeep` is **force-added** past the gitignore — the dir's *contents* are
gitignored (not backup-worthy), but the empty dir is tracked (same pattern as chatterbox's
`logs/`, `outputs/`).

## Moving tiers

A one-time **host** data move (`mv volumes/<name> volumes_local/<name>`), called out in the
migration note — never done to live data automatically.
