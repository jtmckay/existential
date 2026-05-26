# CLAUDE.md

This file provides guidance to Claude Code when working in this repository.
**Keep it current.** Whenever you add or remove a service, script, or change the repo
structure in a way described here, update the relevant section before finishing the task.

---

## Project Overview

Existential is a curated homelab stack: AI tools, workflow automation, note-taking, file
management, and productivity applications. All services are Docker containers on a bridge
network named `exist`.

---

## Principles

Keep conventions tight. The conventions ARE the documentation — someone new to this repo
should be able to navigate it without an onboarding doc, because every service looks like
every other service. **Match existing patterns first; invent only when you must.**

1. **Custom logic is plain bash.** Reach for shell scripts before Python, Node, or any
   other runtime. Bash is already on every host and in the `existential-adhoc` container.
2. **Configuration is YAML.** Compose files, automations, dashy, caddy, prometheus, decree
   cron — all YAML. `.env` is for secrets and host-specific values only; never use it as
   a substitute for structured config.
3. **Repeatable work is a decree routine.** If a script needs to run more than once — on a
   schedule, after a webhook, in response to a message — it lives in
   `automations/routines/`. Not host cron, not a one-off `docker exec`, not a sibling
   `exist.<action>.sh`. One-shots stay as `exist.<action>.sh`; recurring work is decree's
   job.
4. **Services set themselves up deterministically.** Each service ships an
   `exist.initial.sh` that brings it from "fresh container" to "ready to use". Re-running
   should be a no-op (sentinel-gated). Prompts only when there's truly no deterministic
   answer.
5. **Services validate themselves.** Each service ships an `exist.test.sh` that confirms
   it is fully operational and prints copy-pasteable remediation for anything broken. See
   "Service test scripts" below.
6. **Tests are read-only.** No stacking state. A test must not leave artifacts behind.
   Prefer pure observation (HTTP probes, `docker inspect`, log scans) over create-and-
   delete dances. If a write is unavoidable, the cleanup runs in a `trap` and is verified.
7. **Ignore the `graveyard/`.** Archived services don't get new initial scripts, tests, or
   docs. If something graveyarded needs work, lift it out first; otherwise leave it alone.

When in doubt, copy the closest existing example and adapt — divergence from the
conventions makes this repo harder to read for everyone.

---

## Directory Structure

```
ai/           AI tools
services/     Core applications
nas/          Storage layer
hosting/      Infrastructure
automations/  Decree automation engine (working directory)
src/          Setup and utility scripts
decree/       Decree source code (cloned, read-only reference)
site/         Docusaurus documentation
graveyard/    Archived/deprecated solutions
```

### ai/
`chatterbox` `hermes` `librechat` `lightrag` `mcp` `ollama` `open-webui` `whisper`

### services/
`actual-budget` `appsmith` `dashy` `decree` `immich` `it-tools` `logseq`
`lowcoder` `mealie` `nocodb` `ntfy` `vikunja`

### nas/
`collabora` `minio` `nextcloud` `redis` *(trueNAS is external — config note only)*

### hosting/
`caddy` `cloudflare` *(certs only — no container)* `grafana` `loki` `pihole`
`portainer` `prometheus` `uptime-kuma`

### automations/ (Decree working directory)
Mounted into the `decree` container at `/work/.decree`.

```
automations/
├── config.yml          Routine registry, hooks, AI tool config
├── router.md           Prompt template for automatic routine selection
├── processed.md        Tracks completed migrations
├── routines/           Routine shell scripts
├── hooks/              Lifecycle hook scripts (beforeAll/afterAll/etc.)
├── lib/                Shared shell helpers (precheck.sh, etc.)
├── cron/               Scheduled trigger files
├── inbox/              Message queue (dead/ subdir for failed messages)
├── outbox/             Follow-up messages written by routines; decree relays to inbox
├── emails/             Archived email messages (written by gmail routine)
└── runs/               Execution logs — one dir per message (audit trail)
```

#### services/decree/decree-backup/ — isolated backup daemon
The `decree-backup` container is the **only** container that mounts the master
`.env` (so it has DB credentials) AND the only one that mounts every backup
target volume at `/volumes/<name>` (so it can tar / wipe / extract them). It
runs both `db-backup` (logical SQL dumps) and `volume-backup` (file-level
tars) on its own cron schedule, kept separate from the main `decree` daemon
so neither secret has to leak there.

```
services/decree/decree-backup/
├── config.yml          Routine registry — db-backup + volume-backup enabled
├── cron/               Active cron triggers (gitignored; populate from cron.example_/)
├── cron.example_/      Templates: db-backup-{nightly,weekly}.md, volume-backup-{nightly,weekly}.md
├── processed.md        Tracks completed migrations
└── inbox/, outbox/     Runtime state (gitignored)
```

Routines, `lib/`, and `hooks/` are mounted **read-only** from `automations/`
so both daemons share the same code without duplication. `runs/` is mounted
**writable** from `automations/runs/` so execution logs from both daemons
land in the same audit trail (and `clean-runs` prunes them uniformly).

The list of databases (DB engine + container + credential env vars) and
volumes (volume + consumer containers) lives in each cron file's frontmatter
— `TARGETS:` / `VOLUMES:` blocks. No separate registry to keep in sync; to
add a target, edit the cron file. For volumes, also add a matching mount
line to the `decree-backup` service in
`services/decree/docker-compose.yml.example` so the container can see it.

### src/
Holds **general-purpose** infra and utility code only. Service-specific setup
scripts live alongside their services as `exist.<name>.sh` (see next section).

```
src/
├── generate-compose.py             Merges enabled services → docker-compose.yml
├── interactive_cli_replacer.sh     Legacy EXIST_CLI prompter (not currently sourced; existential.sh has an inline equivalent with DEFAULT_FROM support)
├── lib/
│   ├── exist-test.sh               Shared helpers for per-service exist.test.sh (probes, output, skip-if-disabled)
│   ├── generate_hex_key.sh         `generate_hex_key N` / `generate_32_char_hex` / `generate_64_char_hex` — sourced by existential.sh
│   └── generate_password.sh        `generate_24_char_password` — sourced by existential.sh
├── setup/
│   ├── backup.sh                   Configure rclone backup destination
│   ├── backup-restore.sh           Interactive restore — DB dump or Docker volume
│   └── rclone.sh                   rclone remote configuration
└── test/
    ├── run-all.sh                  Test suite orchestrator — runs src/test/* + every enabled exist.test.sh
    ├── test-syntax.sh              Lint every script (src/ + every exist.*.sh)
    ├── test-gmail.sh               Validate Gmail credentials (routine-scoped, not service-scoped)
    └── test-rclone.sh              Test rclone remote connectivity
```

**Sourceable utilities** (`src/lib/*.sh`): standalone scripts with both a callable
function and a CLI entrypoint. Source them from `existential.sh` or any other
script instead of reimplementing the logic — see [[feedback_sourceable_utilities]].

Per-service tests (`<cat>/<slug>/exist.test.sh`) own the service-scoped checks.
The general `src/test/test-*.sh` scripts cover only things that don't belong to any
one service (syntax linting, rclone, Gmail routine credentials).

### Service setup scripts (`exist.<name>.sh`)

Each service owns its setup, test, and on-demand action code in its own directory:

```
<category>/<slug>/
├── docker-compose.yml(.example)
├── exist.initial.sh          # auto-run on first init — sentinel-gated
├── exist.test.sh             # validate the service is fully operational (read-only)
├── exist.<action>.sh         # optional sibling scripts for refresh/cron/etc.
└── .exist.initialized        # sentinel (gitignored) — touched after success
```

- **`exist.initial.sh`** runs once on first init: `./existential.sh` checks each
  enabled service, runs it if `.exist.initialized` is missing, then touches the
  sentinel on success. Re-run manually with `./existential.sh setup <slug>` or
  force everything with `./existential.sh --force`.
- **`exist.test.sh`** — see "Service test scripts" below.
- **`exist.<action>.sh`** are on-demand sibling scripts: `./existential.sh setup
  <slug> <action>` runs them. Examples below.
- **Runtime:** each script decides whether it runs on host or self-elevates
  into the `existential-adhoc` container. Adhoc-needing scripts include a
  small `if [[ -z "$IN_CONTAINER" ]]; then exec docker compose run …` block
  at the top.

Current inventory:

| Path | Trigger |
|---|---|
| `hosting/pihole/exist.initial.sh` | `./existential.sh setup pihole` — router DNS walkthrough, runs FIRST |
| `hosting/caddy/exist.initial.sh` | `./existential.sh setup caddy` — optional public-domain (EXIST_PUBLIC_DOMAIN) |
| `services/actual-budget/exist.initial.sh` | `./existential.sh setup actual-budget` |
| `services/ntfy/exist.initial.sh` | `./existential.sh setup ntfy` |
| `services/decree/exist.gmail-sync.sh` | `./existential.sh setup decree gmail-sync` |
| `services/decree/exist.gmail-labels.sh` | `./existential.sh setup decree gmail-labels` |
| `services/decree/exist.gmail-transactions-cron.sh` | `./existential.sh setup decree gmail-transactions-cron` |

**Init ordering:** `run_initials()` walks `SERVICE_CATEGORIES` in this order:
`hosting → nas → ai → services`. Pihole's router walkthrough is in hosting,
so it runs before service-specific initials that might rely on `.internal`
hostname resolution.

### Service test scripts (`exist.test.sh`)

Every enabled service ships an `exist.test.sh` next to its compose file. The script
validates the service is fully operational from its own perspective — container running,
listening port, API smoke check, required env vars present, dependencies reachable, etc.
— and prints clear, copy-pasteable remediation when anything fails.

Hard rules:
- **Read-only.** No stacking state. Pure observation only (`docker inspect`, `docker
  exec … <ro command>`, HTTP probes, log scans). If a write is unavoidable, do the
  cleanup in a `trap` and verify the cleanup ran.
- **Service-scoped.** Tests check the service in front of them. They do not cascade into
  testing every dependency — flag a missing dep, don't recursively test it. Cross-service
  flow is the job of a separate orchestration test, not the per-service one.
- **Exit non-zero on failure.** Each failed check prints what was checked, what was
  observed, and what to do about it. The script as a whole exits non-zero if any check
  failed.
- **Skip cleanly when disabled.** If `EXIST_IS_<CATEGORY>_<SLUG>` is false, the test
  exits 0 with a "skipped — disabled" message so it stays safe to run in bulk.
- **Same runtime pattern as other `exist.*.sh`.** Run on host where possible; self-
  elevate into `existential-adhoc` when network or tooling demands it.

Suggested output format (not enforced, but copy it if you can):

```
[<slug>] container running         OK
[<slug>] http://<container>:<port> OK
[<slug>] <some thing>              FAIL
        observed: <symptom>
        fix:      <command or pointer>
```

Triggered via:

```bash
./existential.sh test                  # All enabled services (plus general src/test/*)
./existential.sh setup <slug> test     # One service
```

Tests for general infra (not tied to a single service — e.g., rclone, syntax linting)
stay in `src/test/`. Tests for a specific service belong in that service's directory
as `exist.test.sh`.

---

## Setup

### Full setup (first run)
```bash
./existential.sh
```

1. Render `.env.exist.example` → `.env.exist` (prompts for any `EXIST_CLI` values)
2. For every service with `EXIST_IS_<CATEGORY>_<SLUG>=true`, copy its `.example`
   files into counterparts and run placeholder replacement. `automations/` is
   processed when `EXIST_IS_SERVICES_DECREE=true`. Disabled services are **skipped**
   so their secret/template files never land on disk.
3. For each enabled service with `exist.initial.sh` and no `.exist.initialized`
   sentinel, run the script and touch the sentinel on success.
4. Merge enabled services into a unified `docker-compose.yml` (and write the
   master `.env`) via the existential-adhoc container.

### Targeted commands
```bash
./existential.sh --force        # Re-render existing files + re-run all initials
./existential.sh examples       # Only process .example files
./existential.sh initials       # Only run pending exist.initial.sh scripts
./existential.sh compose        # Only regenerate docker-compose.yml and master .env

# Setup dispatch — general utilities (src/setup/<name>.sh):
./existential.sh setup backup           # Configure rclone backup destination
./existential.sh setup backup-restore   # Interactive DB or volume restore
./existential.sh setup rclone           # Configure rclone remotes

# Setup dispatch — service-specific (<category>/<slug>/exist.<action>.sh):
./existential.sh setup                  # List every available setup action
./existential.sh setup <slug>           # Run <slug>'s exist.initial.sh
./existential.sh setup <slug> <action>  # Run <slug>'s exist.<action>.sh
# Examples:
./existential.sh setup actual-budget
./existential.sh setup ntfy
./existential.sh setup decree gmail-sync
./existential.sh setup decree gmail-labels
./existential.sh setup decree gmail-transactions-cron

# Backups (both DBs and Docker volumes run inside decree-backup on its own
# cron — see services/decree/decree-backup/cron.example_/, edit each cron
# file's TARGETS / VOLUMES frontmatter to add or remove targets):
./existential.sh backup db      [nightly|weekly]  # Trigger db-backup now
./existential.sh backup volumes [nightly|weekly]  # Trigger volume-backup now
./existential.sh backup restore                   # Same as: setup backup-restore

./existential.sh test                    # Run all enabled-service exist.test.sh + src/test/*
./existential.sh setup <slug> test       # Test one service (read-only validation)
./existential.sh validate                # Conventions + drift checks
./existential.sh validate conventions    # Slugs synced across compose/piHole/Caddy/dashy
./existential.sh validate drift          # What re-rendering would change
```

### Manual service setup
```bash
cp services/foo/.env.example services/foo/.env
# edit .env, then:
docker compose up -d
```

---

## Placeholder System

| Placeholder | Behavior |
|---|---|
| `EXIST_CLI` | Prompts user for input during setup |
| `EXIST_24_CHAR_PASSWORD` | Generates a unique 24-character password |
| `EXIST_32_CHAR_HEX_KEY` | Generates a unique 32-character hex key |
| `EXIST_64_CHAR_HEX_KEY` | Generates a unique 64-character hex key |
| `EXIST_TIMESTAMP` | Current timestamp (`YYYYMMDD_HHMMSS`) |
| `EXIST_UUID` | UUID |
| `EXIST_*` | Value of matching variable from root `.env.exist` |

An `EXIST_CLI` prompt can opt into a fallback by adding a comment immediately
above the line: `# DEFAULT_FROM: EXIST_FOO`. If the user enters blank,
the value of `EXIST_FOO` (already written earlier in the same file) is
used. Used today for `EXIST_PEER_HOST_IP` defaulting to `LOCAL_HOST_IP`.

---

## Env var naming convention

**Top-level (`.env.exist.example`):**
- Every key starts with `EXIST_`. The legacy `EXIST_DEFAULT_*` and
  `EXIST_ENABLE_*` prefixes are no longer accepted.
- Service-enablement flags use `EXIST_IS_<CATEGORY>_<SLUG>=true|false`
  (e.g., `EXIST_IS_AI_HERMES`, `EXIST_IS_SERVICES_MEALIE`).
- Shared cross-service values live here and are referenced as `${EXIST_FOO}`
  in service compose files — no need to copy them into each service's `.env`.

**Per-service (`<cat>/<slug>/.env.example`):**
- Every key starts with `<SLUG>_` (folder name uppercased; hyphens → underscores).
  `actual-budget` → `ACTUAL_BUDGET_`, `open-webui` → `OPEN_WEBUI_`.
- Image-required names (`MYSQL_USER`, `GF_*`, `LLM_BINDING`, etc.) get mapped
  in `docker-compose.yml.example`: `MYSQL_USER: ${MEALIE_MYSQL_USER}`.
- Files copied wholesale from an upstream project that uses `env_file:` (e.g.,
  LibreChat, Immich, LightRAG) can opt out with a top-of-file marker:
  `# convention-exempt: upstream-env`.

Run `./existential.sh validate conventions` to check both rules.

---

## NFS volume convention

- A volume that declares `driver_opts: type: nfs` must also set `o:` (with
  `addr=…`) and `device:` — half-configured volumes silently fall back to
  plain local storage.
- Conventional name: `<service>_<purpose>_data` (snake_case), matching the
  trailing segment of `device:`. E.g., `mealie_pg_data`, `vikunja_db_data`.
- Service compose files reference TrueNAS via `${EXIST_TRUENAS_SERVER_ADDRESS}`
  and `${EXIST_TRUENAS_CONTAINER_PATH}` directly — no per-service copy needed.
- Validation runs against the generated master `docker-compose.yml`, not the
  per-service templates.

---

## Container naming convention

Every container in a service's compose file must be prefixed with the
service's slug (the folder name). For a service in `hosting/loki/`:

- `loki` (the primary container — slug-only is fine)
- `loki-promtail` ✓
- `promtail` ✗ — opaque, doesn't say which service it belongs to

Reason: reading `docker ps` should make it immediately clear which service
each container belongs to. No having to look up what "pushgateway" or
"promtail" is.

The same rule applies to support filenames where the container's identity
is part of the name (e.g., `loki-promtail-config.yaml`, not
`promtail-config.yaml`). Files specific to the primary service can use the
slug alone (e.g., `loki-config.yaml`).

The validation script (`./existential.sh validate conventions`) catches
container names that don't start with their folder's slug.

---

## Networking convention

Two layers — pick the right one for the call site.

**Browser / cross-machine traffic → `https://<slug>.internal`** (the slug matches
the service's `container_name`, lowercase-hyphenated):

- **piHole** (`hosting/pihole/docker-compose.yml`) holds a record per slug,
  active line pointing at `EXIST_LOCAL_HOST_IP` and a commented PEER
  alternative. Flip the comment to migrate a service between machines.
- **Caddy** (`hosting/caddy/Caddyfile`) fronts every slug with `tls internal`
  and reverse-proxies to `<container>:<port>`. Browsers see a cert from
  Caddy's internal CA — install the root once per device for green locks.
- **Dashy** (`services/dashy/dashy-conf.yml`) links every navigable slug.
- **`.env.exist`** holds `EXIST_LOCAL_HOST_IP` (this machine) and
  `EXIST_PEER_HOST_IP` (the other machine; defaults to LOCAL).

**Container-to-container traffic → `http://<container>:<port>`** (Docker's
built-in service DNS on the `exist` network):

- Service env vars in `*/docker-compose.yml.example` and `.env.example` use
  this form (e.g., `OLLAMA_BASE_URL=http://ollama:11434`).
- Automation routines (`automations/routines/*.sh`) and shared libs use this
  form for their default `${X_URL:-http://service:port}` fallbacks.
- Faster (no Caddy hop), simpler (no TLS), and doesn't need Caddy CA trust
  inside the calling container — which would otherwise require per-image
  surgery for each base distro / runtime.

When adding a service, the slug appears in three convention files (piHole,
Caddy, Dashy if navigable). Cross-service references inside service env vars
stay on Docker DNS. Run `./existential.sh validate conventions` to verify
the three are in sync.

---

## Service Enablement

Toggle services via `EXIST_IS_*=true/false` in the root `.env.exist`, then:

```bash
./existential.sh compose
```

`src/generate-compose.py` runs in the `existential-adhoc` container. It reads
`EXIST_IS_*`, discovers `docker-compose.yml` files at depth 2, adjusts relative
paths from the repo root, and merges services/volumes/networks. The previous
`docker-compose.yml` is archived as `docker-compose-<timestamp_ms>.yml` before writing.

---

## Architecture

- Each service has its own `docker-compose.yml` and `.env` file
- All services connect to the `exist` bridge network
- Secrets are stored in `services/<name>/secrets/` (gitignored)
- The `existential-adhoc` container (profile: `adhoc`) handles setup tasks requiring
  non-standard tools — mounts `src/` at `/src` and the repo at `/repo`
- Documentation lives in `site/` (Docusaurus)

---

## Decree (Automations)

Quick reference:
- Routines: `automations/routines/<name>.sh` + registered in `automations/config.yml`
- Cron jobs (main decree): `automations/cron/<name>.md`
- Cron jobs (decree-backup): `services/decree/decree-backup/cron/<name>.md`
- Webhook endpoints: `services/decree/webhook/config.yml`
- Run commands via: `docker exec decree decree <command>`
- DB-backup commands via: `docker exec decree-backup decree run db-backup`

### Cron routine setup convention

Both decree daemons have a paired `cron/` (active, gitignored) and
`cron.example_/` (tracked templates) directory. The `.example_` suffix
intentionally does **not** match `*.example`, so existential.sh never
auto-renders these — they're manual.

To activate a cron template:

```bash
cp <dir>/cron.example_/<name>.md <dir>/cron/<name>.md
docker compose -f services/decree/docker-compose.yml restart <daemon>
```

The active `cron/` is mounted into the daemon read-only; on restart, decree
parses the frontmatter (`cron:`, `routine:`, extra keys exposed as env vars
to the routine) and schedules accordingly. The `clean-runs` routine prunes
old run logs across both daemons (because both share `automations/runs/`).

---

## Testing Services

Every service ships an `exist.test.sh` that validates the service is fully operational
without changing any state. See "Service test scripts" above for the convention.

```bash
./existential.sh test                  # All enabled services + general src/test/*
./existential.sh setup <slug> test     # One service — read-only validation
docker ps | grep <slug>                # Container running?
docker logs <container_name>           # Recent logs
```

If a service is missing `exist.test.sh`, add it — don't reach for ad-hoc `curl` or
`docker exec` invocations. The test file is the canonical, repeatable answer to "is
this thing working?".

---

## Keeping This File Current

Update CLAUDE.md in the same task whenever you:
- **Add a service** — add it to the correct category in the directory structure section,
  and ship both `exist.initial.sh` and `exist.test.sh` with it
- **Remove a service** — remove it from that section
- **Add or remove a script** in `src/` — update the src/ tree
- **Add or remove a Decree routine or cron file** — no change needed here; those are
  covered by the `/decree` command which reads the live files
- **Change a setup command** (e.g. new `./existential.sh setup <name>` subcommand) —
  update the Targeted commands section
- **Add a new top-level directory** — add it to the directory structure overview
- **Introduce a new convention** — add a dedicated section under the existing convention
  blocks (env var, NFS, container naming, networking, …). Conventions only work if
  they're written down.

Do not let CLAUDE.md describe things that no longer exist. If you notice a stale entry
while working on an unrelated task, fix it in the same commit.
