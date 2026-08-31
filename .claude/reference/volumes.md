# Volumes

**We never use Docker-managed volumes** — they're opaque and re-init from the image (wrong UID
on NFS). Every volume is a **host bind mount**: visible, inspectable, correctly-owned.

A template refers to a volume by **bare name** and declares it in `x-exist-volumes` (below);
`generate-compose.ts` materialises that into an absolute host path. Paths that are not volumes —
a mounted config file, a service-dir directory — stay relative and are only normalised
(`../../<dir>` → `./<dir>`, prepending the service dir). The **generated** `docker-compose.yml`
therefore contains no bare names and no top-level `volumes:` block, so `docker volume ls` stays
empty; `validate conventions` enforces that on the generated file.

## One directory, declared properties

Every volume lives in **`volumes/<name>`**. There is no second root — what a volume *is* comes
from its declaration, never from which folder it sits in.

Each service declares its volumes in an **`x-exist-volumes`** block, a top-level key in its
`docker-compose.exist.yml` (the same overlay pattern as `x-exist-gpu`: read by the generator,
stripped from the output). Mounts then reference the volume by bare name:

```yaml
services:
  nextcloud:
    volumes:
      - nextcloud_data:/var/www/html/data
      - nextcloud_sql_data:/var/lib/mysql

x-exist-volumes:
  nextcloud_data:     { nfs: true }
  nextcloud_sql_data: { db: true }
```

| Property | Default | Meaning |
|---|---|---|
| `nfs`    | `false` | May live on the NAS export. When `EXIST_NFS_HOST_MOUNT` is set, `generate-compose.ts` resolves the source to `<mount>/<name>`; otherwise it stays in `volumes/`. |
| `db`     | `false` | Holds an embedded or managed database (SQLite WAL, bbolt, a TSDB, a postgres/mysql/mongo data dir). NFS corrupts these — `validate conventions` rejects `db: true` together with `nfs: true`. |
| `backup` | `false` | `decree-backup` archives it into `<name>_backup`. |

**A bare name with no declaration is a hard error.** `generate-compose.ts` exits non-zero and
prints the block to add, rather than letting compose fall through to a Docker-managed volume —
opaque, re-inits from the image, wrong UID on NFS. That check is the reason this repo can use
bare names safely at all.

## The suffix says whether it is safe to delete

The name's suffix is the thing a human reads before running `rm -rf`, so it is **enforced** by
`validate conventions` rather than left to convention:

| Suffix | For | `reset` |
|---|---|---|
| `_data`   | user data or a live database | never touched |
| `_backup` | archives of a `_data` volume, written by `decree-backup` | never touched |
| `_cache`  | regenerable — models, HF caches, scratch; refetched or rebuilt on next start | offers to delete |

`_cache` may not declare `backup: true` (there is nothing worth archiving). Name volumes
`<service>_<purpose>_<suffix>`.

A `_backup` volume only exists once something mounts and writes it, and today nothing does:
`db-backup` and `volume-backup` rclone straight to a remote (`EXIST_BACKUP_RCLONE_REMOTE`)
rather than to a local archive dir. Don't create the directory ahead of a template that declares
it — an unmounted, undeclared `volumes/<name>_backup` is just litter, and the generator makes it
the moment a template declares one.

**Decision rule:** does losing it cost the user anything they can't get back? → `_data`. Would the
stack simply re-download or rebuild it? → `_cache`. An embedded database is always `_data` **and**
`db: true`.

## No .gitkeep

Volume directories are **not** tracked and carry no `.gitkeep`. `volumes/` is gitignored
wholesale. The directories are created by `generate-compose.ts` for exactly the services that are
enabled — `ensureBindSource` for relative binds, and the named-volume branch for declared volumes
— running inside adhoc as the host `uid:gid`, so they land correctly owned before anything can
`docker compose up`.

That ordering is guaranteed, not hoped for: the root `docker-compose.yml` is itself generated and
gitignored, so a checkout cannot start the stack without having run `./existential.sh` first.

This replaced a committed `.gitkeep` in every bind dir, which had two problems worth remembering:

- **An image may treat `.gitkeep` as content.** The nextcloud entrypoint populates and chowns
  `config data custom_apps themes` only while it sees each as *empty*
  (`directory_empty "/var/www/html/$dir"`). One tracked file locked it out of all four: the config
  fragments were silently skipped, and `data` never got its `--chown www-data:root`, so apache
  (uid 33) could not write, `occ maintenance:install` failed ten times, and the browser got the
  **setup wizard** instead of a login page. An empty generated directory has neither problem, and
  `nas/nextcloud/exist.test.sh` asserts `"installed":true` so the fatal case cannot pass the
  health gate.
- **A tracked file inside a dir the container locks down breaks git.** An installed nextcloud
  chmods its data dir to `0770 www-data`; the host user cannot traverse it, and every later
  `git status` failed with *Permission denied*.

If an image needs a directory to be empty at first start, it now simply is.

## Moving a volume between properties

Change the declaration and, if the name changes, `mv volumes/<old> volumes/<new>` on the host with
the stack down. Nothing moves live data automatically.

### What "root-creates it" actually costs

This is not cosmetic. When a bind-mount source does not exist, the daemon creates it as an empty
`root:root` directory, and three things follow:

- The container sees an **empty directory** where the image had files. `ai/hermes` mounts
  `hermes_install/{.venv,ui-tui,gateway,node_modules}`, which its own `exist.initial.sh` extracts
  from the image — a `docker compose up` that beats the renderer shadows hermes' binaries and it
  restarts forever with exit 127.
- The next render can't clean up: `rm -rf` on a root-owned dir fails for the host user, and under
  `set -e` that aborts the whole run.
- `reset` dies too, on the first `mkdir -p` under a root-owned `archive/`.

The defence is `adjustVolume` in `src/generate-compose.ts`, which pre-creates every bind source
it rewrites — declared volumes via the named-volume branch, everything relative via
`ensureBindSource` — running inside adhoc as the host uid:gid so each dir lands correctly owned.
It skips sources with a file extension, since a *file* mount must not become a directory, and
skips a destination that has a sibling `<name>.exist.*` template for the same reason.

Neither defence repairs a checkout that already went wrong: `./existential.sh run fix-permissions`
does that, borrowing root from a throwaway container rather than asking for sudo.

## Moving tiers

A one-time **host** data move (`mv volumes/<name> volumes_local/<name>`), called out in the
migration note — never done to live data automatically.
