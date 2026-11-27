---
machine: repo_develop
---
# A service is a folder: a flag, templates rendered once, one compose file, one network

## Overview

A homelab stack collects services, and each one added is one more thing to keep working. The
whole model has to fit in a sentence, so adding a service stays adding a folder: a flag per
service folder, render that service's templates, merge everything enabled into one compose
file and one `.env`, run it on one network. No registry, no orchestrator.

## Outcome

- **The flag comes from the path.** `<category>/<slug>/` is enabled by
  `EXIST_IS_<CATEGORY>_<SLUG>=true|false` in `.env.shared`; a disabled service is skipped
  entirely: no template renders, no secret is generated, nothing lands on disk.
- **Templates render once.** Every `*.exist.*` file renders to its name without `.exist`,
  filling generated secrets and `EXIST_CLI` answers (a `# DEFAULT: <value>` literal above the
  line is the only default form). A rendered file is never re-rendered. Two exceptions reach
  an existing install: a rendered `.env*` gets every key its template has gained appended
  (existing values, blanks included, never touched), and a rendered compose file whose
  `image:` differs from its template's is listed and updated if the person says yes (without
  asking when there is no terminal). A file with nothing a person could lose says `DO NOT
  EDIT` and is regenerated, unless its header says `# EXIST_KEEP: true`.
- **One compose file.** `src/generate-compose.ts` merges every enabled service's
  `docker-compose.yml` into the root one, which is never edited by hand, and every `.env` into
  the root `.env`. It writes the `exist` network as Compose's own bridge (never `external`,
  never created by hand), caps every container's json-file log at 3 × 10 MB, and rewrites GPU
  reservations from `EXIST_GPU_VENDOR`, merging a service's `x-exist-gpu.<vendor>` block.
- **Every service looks alike.** Containers are prefixed with the slug; run as
  `${EXIST_PUID}:${EXIST_PGID}` (or `PUID`/`PGID` for s6-style images), never a literal uid,
  never root; `restart: unless-stopped`; `deploy.resources.limits.memory` sized at 2–3× idle;
  telemetry off with the upstream's own setting, or one line on its docs page saying it cannot
  be. Per-service env keys start `<SLUG>_`, shared ones `EXIST_`, each with one informative
  comment line.
- **Volumes are bind mounts** under `volumes/<name>`, declared in the service's
  `x-exist-volumes:` with a suffix that says whether it is safe to delete (`_data`, `_share`,
  `_backup`, `_cache`); a database is `db: true` and never `nfs: true`. Anything gitignored is
  a volume. No `.gitkeep`: the generator makes the folders.
- **A service sets itself up.** `exist.initial.sh` runs on every `./existential.sh`
  (idempotent, no sentinels); config only the service can reach is trued up by its
  `entrypoint.sh` at each start; post-startup setup is a decree order file of a plugin; every
  service ships `exist.test.sh`; on-demand actions are `exist.<action>.sh`, run with
  `./existential.sh run <slug> <action>`.
- **Addressing.** Containers reach each other over Docker DNS (`http://<container>:<port>`);
  browsers reach add-ons through Caddy (`https://<slug>.<domain>`); a service that is off here
  resolves to the controller's address.

## Constraints

- `validate conventions` enforces what it can: prefixes, flags, volume suffixes and
  declarations, memory limits, `restart`, user, telemetry lines, one docs page per service.
- A new service is a new folder; nothing else in the repo lists it.

## Acceptance Criteria

- **Given** a new folder `ai/foo/` with a `docker-compose.exist.yml` and its flag on
  **When** `./existential.sh` runs
  **Then** `foo` is in the generated `docker-compose.yml` on the `exist` network, with a log cap
- **Given** a rendered `.env` and a template that gained a key
  **When** `./existential.sh` runs
  **Then** the key is appended and every existing value is unchanged
- **Given** `./existential.sh validate conventions`
  **Then** it exits 0
