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

## Primary Goal: Don't Reinvent the Wheel

**Before building anything — a script, a routine, a service, a utility — stop and ask:
does this already exist?**

This stack is called *Existential* for a reason. It is deliberately curated. Every tool
added is a tool that must be maintained, understood, and kept working. The goal is not to
accumulate — it is to compose the right set of existing pieces.

Before writing new code:
- Check if a service in the stack already does it (hermes has skills; decree has routines)
- Check if a shell one-liner or standard Unix tool handles it
- Check if an existing routine or helper in `automations/` covers the case
- Ask: is there an npm package, CLI, or API that already solves this cleanly?

**If something already exists and works, use it. Do not convert, reimplement, or
"standardize" working code unless there is a concrete, specific problem to solve.**

One exception: scripts we author and maintain should be written in a language the team
can actually maintain. For this project that means bash (preferred) or TypeScript/NodeJS
for anything bash can't handle cleanly — not Python. "Different language" is only a
problem when it's a language we own and can't debug. External tools (hermes skills,
third-party services, upstream configs) stay in whatever language they were written in.

---

## Principles

Keep conventions tight. The conventions ARE the documentation — someone new to this repo
should be able to navigate it without an onboarding doc, because every service looks like
every other service. **Match existing patterns first; invent only when you must.**

1. **Custom logic is plain bash, then TypeScript.** Reach for shell scripts first. When
   bash becomes cumbersome, use TypeScript (run via `tsx` inside the decree/adhoc
   container — not installed on the host). Do not use Python for scripts we own; Python
   is only acceptable in external tooling already written in it (e.g. hermes skills).
2. **Configuration is YAML.** Compose files, automations, dashy, caddy, prometheus, decree
   cron — all YAML. `.env` is for secrets and host-specific values only; never use it as
   a substitute for structured config.
3. **`src/` is for host-run scripts. `automations/` is for everything else.** Scripts in
   `src/` run directly on the host (or self-elevate into `existential-adhoc`). Scripts that
   run on a schedule, respond to webhooks, or are triggered by decree belong in
   `automations/shared_routines/` and are enabled through decree's config. Shared code used across
   routines lives in `automations/lib/` — entirely separated from `src/`. If it runs in a
   container on a schedule, it is not a `src/` script.
4. **Repeatable work is a decree routine.** If a script needs to run more than once — on a
   schedule, after a webhook, in response to a message — it lives in
   `automations/shared_routines/`. Not host cron, not a one-off `docker exec`, not a sibling
   `exist.<action>.sh`. One-shots stay as `exist.<action>.sh`; recurring work is decree's
   job.
5. **Services set themselves up deterministically.** Pre-startup filesystem work
   lives in `exist.initial.sh` (idempotent, runs every `./existential.sh`).
   Post-startup automated setup lives in decree migrations (run once after
   `exist.test.sh` passes). Interactive/manual steps are documented as quest guides.
6. **Services validate themselves.** Each service ships an `exist.test.sh` that confirms
   it is fully operational and prints copy-pasteable remediation for anything broken. See
   "Service test scripts" below.
7. **Tests are read-only.** No stacking state. A test must not leave artifacts behind.
   Prefer pure observation (HTTP probes, `docker inspect`, log scans) over create-and-
   delete dances. If a write is unavoidable, the cleanup runs in a `trap` and is verified.
8. **Ignore the `graveyard/`.** Archived services don't get new initial scripts, tests, or
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
volumes/      Persistent volume directories (bind mounts when NFS not configured)
decree/       Decree source code (cloned, read-only reference)
site/         Docusaurus documentation
graveyard/    Archived/deprecated solutions
```

### ai/
`chatterbox` `comfyui` `hermes` `lightrag` `mcp` `ollama` `open-webui` `whisper`

### services/
`actual-budget` `appsmith` `dashy` `decree` `homeassistant` `immich` `it-tools` `logseq`
`lowcoder` `mealie` `nocodb` `ntfy` `vikunja`

### nas/
`collabora` `minio` `nextcloud` `redis` *(NAS/NFS server is external — config note only)*

### hosting/
`caddy` `cloudflare` *(certs only — no container)* `docker-daemon` *(daemon.json — no container)* `grafana` `loki` `pihole`
`portainer` `prometheus` `uptime-kuma`

### automations/ (shared decree code)
Mounted read-only into every decree daemon at the paths shown. Contains only
shared code — no daemon-specific state.

```
automations/
├── shared_routines/    Routine shell scripts (shared across all decree daemons)
├── lib/                Shared shell helpers (precheck.sh, hooks/, etc.)
│   └── hooks/          Lifecycle hook scripts (config-watch.sh, afterEach.sh)
├── runs/               Execution logs — one dir per message, all daemons write here
└── secrets/            rclone config, API keys (gitignored — .gitkeep tracked)
```

### services/decree/decree/ — main decree daemon state
Config, cron templates, and runtime dirs for the main `decree` daemon. All
runtime dirs (`cron/`, `inbox/`, `outbox/`, `emails/`, `processed.md`) are gitignored.

```
services/decree/decree/
├── config.exist.yml    Routine registry, AI tool config (template → config.yml)
├── router.md           Prompt template for automatic routine selection
├── cron.example/      Cron templates (copy to cron/ to activate)
├── cron/               Active cron triggers (gitignored)
├── inbox/              Message queue (gitignored)
├── outbox/             Follow-up messages (gitignored)
├── emails/             Archived email messages (gitignored)
└── processed.md        Migration tracking (gitignored)
```

### Per-service decree sidecars (`<slug>-decree`)
Each backup-eligible service ships a `decree/` subdirectory and a `<slug>-decree`
sidecar container. The sidecar mounts only its own service's volumes and receives
only its own DB credentials via env vars (no master `.env` mount). Credentials
flow through compose exactly as they do for the service's own containers.

```
<category>/<slug>/
├── decree/
│   ├── config.exist.yml    Routine registry + routine_source (template → config.yml)
│   ├── config.yml          Rendered config (gitignored)
│   ├── cron.example/      Cron templates (copy to cron/ to activate)
│   ├── cron/               Active cron triggers (gitignored)
│   ├── inbox/              Runtime state (gitignored)
│   ├── outbox/             Runtime state (gitignored)
│   └── processed.md        Migration tracking (gitignored)
└── docker-compose.exist.yml  # includes the <slug>-decree sidecar
```

All decree daemons (main + sidecars) share `automations/shared_routines/`, `automations/lib/`,
and `automations/runs/` via read-only mounts. The routines directory is mounted as
`/work/.decree/shared_routines` and declared via `routine_source` in each `config.exist.yml`,
so code lives in one place and logs from all daemons land in the same audit trail
(pruned uniformly by `clean-runs`).

Services with decree sidecars:

| Service | Sidecar | Migrations | Backups |
|---|---|---|---|
| `ai/ollama` | `ollama-decree` | pull models + apply Modelfiles | — |
| `services/vikunja` | `vikunja-decree` | create default user | DB (postgres) + volume |
| `services/mealie` | `mealie-decree` | — | DB (postgres) + volume |
| `services/nocodb` | `nocodb-decree` | — | DB (postgres) + volume |
| `services/lowcoder` | `lowcoder-decree` | — | DB (mongo) + volumes |
| `nas/nextcloud` | `nextcloud-decree` | — | DB (mariadb) |
| `services/actual-budget` | `actual-budget-decree` | — | volume |
| `services/appsmith` | `appsmith-decree` | — | volume |
| `ai/hermes` | `hermes-decree` | — | volume |
| `ai/lightrag` | `lightrag-decree` | — | volume |

### src/
Holds **general-purpose** infra and utility code only. Service-specific setup
scripts live alongside their services as `exist.<name>.sh` (see next section).

```
src/
├── generate-compose.ts             Merges enabled services → docker-compose.yml
├── quest.sh                        Interactive onboarding wizard — invoked by `./existential.sh quest`
├── templates.sh                    Render *.exist.* templates — EXIST_CLI (fzf prompts), placeholder substitution; runs inside existential-adhoc
├── quests/                         Quest definitions — one *.yml per quest
│   ├── 01-nas-storage.yml          Numbered quests (01–09): service selection + cron copies
│   ├── 03-automation-and-observability.yml  Fields: name, tagline, services (var+label),
│   ├── …                                   copies (src+dst+label+requires), guide
│   └── auto-*.yml                  Automation quests: guide-only flows with doc links
├── lib/
│   ├── backup-config.sh            Configure rclone backup destination (run via: ./existential.sh run backup-config)
│   ├── backup-restore.sh           Interactive restore — DB dump, SQLite dump, or Docker volume
│   ├── check-versions.sh           Compare pinned image tags vs latest; --update patches .exist.yml files
│   └── rclone.sh                   rclone remote configuration
├── utils/
│   ├── generate_hex_key.sh         `generate_hex_key N` / `generate_32_char_hex` / `generate_64_char_hex` — sourced only
│   └── generate_password.sh        `generate_24_char_password` — sourced only
└── test/
    ├── e2e.sh                      End-to-end harness — fresh clone per quest, docker up --build, gate, test, down
    ├── exist-test.sh               Shared helpers for per-service exist.test.sh (probes, output, skip-if-disabled)
    ├── container-health.sh         Host-side container-state gate — fails on restart-loops/exited/unhealthy (runs where docker is visible, NOT in adhoc)
    ├── run-all.sh                  Test suite orchestrator — runs src/test/* + every enabled exist.test.sh
    ├── test-syntax.sh              Lint every script (src/ + every exist.*.sh)
    ├── test-gmail.sh               Validate Gmail credentials (routine-scoped, not service-scoped)
    ├── test-rclone.sh              Test rclone remote connectivity
    ├── validate-conventions.ts     Convention checks (slug sync across compose/piHole/Caddy/dashy)
    ├── check-drift.ts              Template vs rendered drift report
    └── fixtures/
        └── env.shared              Pre-filled .env.shared for e2e runs (committed, no real secrets)
```

**`src/lib/`** holds interactive setup utilities dispatched by `./existential.sh run`
(`backup-config.sh`, `backup-restore.sh`, `rclone.sh`). See [[feedback_sourceable_utilities]].

**`src/utils/`** holds scripts that are **sourced only** — never run directly
(`generate_hex_key.sh`, `generate_password.sh`). Source them from `templates.sh`
rather than reimplementing the logic.

**`src/test/`** holds all test infrastructure: `exist-test.sh` (shared helper sourced
by every `exist.test.sh`) and the general test scripts (`run-all.sh`, `test-*.sh`,
`validate-conventions.ts`, `check-drift.ts`) that cover things not owned by any one
service. Per-service tests live in their own `<cat>/<slug>/exist.test.sh`.

### Service lifecycle scripts

Three tiers cover everything from first-run to steady-state:

```
./existential.sh run:
  1. Template rendering   src/templates.sh renders *.exist.* → live files
  2. exist.initial.sh     Pre-startup, idempotent, runs every time.
                          Creates files, applies system config, sets permissions.
                          Scripts check for existing state and skip completed work.

docker compose up -d      (user runs this)

On sidecar startup (decree sidecar, after test passes):
  3. exist.test.sh        Sidecar retries until this passes (service is healthy).
  4. decree process       Runs pending migrations from <service>/decree/migrations/.
                          Each migration runs exactly once (tracked in processed.md).

On demand:
  5. exist.<action>.sh    Interactive or manual steps: ./existential.sh run <slug> <action>
                          Documented as quest guides so users know when and why to run them.
  6. exist.test.sh        Read-only validation: ./existential.sh run <slug> test
```

**When to write each:**

| Script | Write when… |
|---|---|
| `exist.initial.sh` | Files, dirs, or system config must exist before the container starts. Must be idempotent — check before acting, never rely on a sentinel. |
| Decree migration `migrations/<name>.md` | Post-startup automated setup: API calls, user creation, DB seeds. Runs once after `exist.test.sh` passes. |
| `exist.<action>.sh` | Interactive or manual on-demand operations a user triggers explicitly. Document in a quest guide. |
| `exist.test.sh` | Always. Every service ships one. Used by both `./existential.sh test` and the sidecar health gate. |

Each service owns these scripts in its own directory:

```
<category>/<slug>/
├── docker-compose.exist.yml  # template → renders to docker-compose.yml
├── .env.exist                # template → renders to .env
├── exist.initial.sh          # pre-startup, idempotent (no sentinel)
├── exist.test.sh             # read-only validation; also the sidecar health gate
├── exist.<action>.sh         # optional on-demand scripts
└── decree/
    └── migrations/           # post-startup one-time setup (decree runs after test passes)
```

- **`exist.initial.sh`** runs on every `./existential.sh` call for enabled services.
  Scripts must be idempotent: check whether the work is already done and return early
  if so. No sentinel files. Failures abort the run.
- **Decree migrations** live in `<service>/decree/migrations/*.md`. The service sidecar
  waits for `exist.test.sh` to pass, then runs `decree process` which executes any
  migration not yet in `processed.md`. Migrations run exactly once per install.
- **`exist.test.sh`** — see "Service test scripts" below. In sidecar context
  (`DECREE_SIDECAR=true`), `skip_if_disabled` and `probe_caddy` are no-ops so the
  test focuses on the service itself, not the full routing stack.
- **`exist.<action>.sh`** are on-demand scripts: `./existential.sh run <slug> <action>`
  runs them. Document them in quest guides so users know when and why.
- **Runtime:** each script decides whether it runs on host or self-elevates
  into the `existential-adhoc` container. Adhoc-needing scripts include a
  small `if [[ -z "$IN_CONTAINER" ]]; then exec docker compose run …` block
  at the top.

Current inventory:

| Path | Trigger |
|---|---|
| `hosting/caddy/exist.public-domain.sh` | `./existential.sh run caddy public-domain` — optional public-domain setup |
| `hosting/docker-daemon/exist.log-rotation.sh` | `./existential.sh run docker-daemon log-rotation` — apply Docker log rotation (daemon.json + reload) |
| `services/actual-budget/exist.setup.sh` | `./existential.sh run actual-budget setup` — connect to budget server, save credentials |
| `services/ntfy/exist.setup.sh` | `./existential.sh run ntfy setup` — save ntfy access token |
| `ai/ollama/exist.pull-models.sh` | `./existential.sh run ollama pull-models` — manual model pull (automated via ollama-decree migrations) |
| `ai/ollama/exist.benchmark.sh` | `./existential.sh run ollama benchmark [model]` — decode-speed (tok/s) benchmark across increasing context sizes |
| `services/vikunja/decree/migrations/01-create-default-user.md` | auto — sidecar runs once after vikunja is healthy |
| `services/decree/exist.gmail-sync.sh` | `./existential.sh run decree gmail-sync` |
| `services/decree/exist.gmail-labels.sh` | `./existential.sh run decree gmail-labels` |
| `services/decree/exist.gmail-transactions-cron.sh` | `./existential.sh run decree gmail-transactions-cron` |
| `services/decree/exist.decree-ui.sh` | `./existential.sh run decree decree-ui` — generate Lowcoder control panel |

**Init ordering:** `run_initials()` walks `SERVICE_CATEGORIES` in this order:
`hosting → nas → ai → services`. Hosting-level setup (e.g. portainer password)
completes before service-level scripts run.

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
./existential.sh run <slug> test     # One service
```

Tests for general infra (not tied to a single service — e.g., rclone, syntax linting)
stay in `src/test/`. Tests for a specific service belong in that service's directory
as `exist.test.sh`.

#### Container-state gate (host-side)

`exist.test.sh` self-elevates into `existential-adhoc`, which has **no docker
socket** — it can only reach services over the network. So a per-service test
**cannot** see a container that is crash-looping, exited, or `(unhealthy)`, and it
is blind to daemons with no network surface (the main `decree` daemon and every
`*-decree` sidecar are `bash` daemons — there is nothing to HTTP-probe).

That gap is covered by `src/test/container-health.sh`, which runs on the **host**
(the only place docker is visible). For every container in a compose project it
asserts `status == running`, no active restart-loop (RestartCount stable across a
short resample), and `Health.Status != unhealthy` — dumping logs and exiting
non-zero on any failure. It is wired into both entry points:

- **`./existential.sh test`** runs it against the live `docker-compose.yml` before
  the adhoc `run-all.sh`.
- **`src/test/e2e.sh`** runs it after `docker compose up -d --build` and **fails the
  quest** if it trips. (e2e always builds with `--build` — compose reuses cached
  images and never rebuilds on a Dockerfile change, so without it e2e can silently
  test a stale image of the committed code.)

The two layers are complementary: `exist.test.sh` proves a service answers
correctly; the host gate proves every container is actually up and not flapping.

#### Daemon healthcheck convention

Containers with an HTTP surface declare a `healthcheck` in their compose file (see
`decree-webhook`). The decree image is built **once** from `automations/Dockerfile` —
`existential-adhoc` (in `existential-compose.yml`) is the canonical builder and tags it
`existential/decree:local`; the main `decree` daemon and every `*-decree` sidecar
reference that tag via `image:` instead of each re-building it (which used to spawn one
1GB image per service per compose project). They differ only by their compose
`volumes:`/env. The shared image sets `WORKDIR /work` so `decree daemon` finds the
project mounted at `/work/.decree`, and bakes a single `HEALTHCHECK`:
`grep -q decree /proc/1/comm`. After `entrypoint.sh` does `exec decree daemon`,
PID 1's comm is `decree`; a mis-built image (no ENTRYPOINT → base `CMD bash`) or a dead
daemon fails the check and shows `(unhealthy)`. The `start-period` is long (330s) so a
sidecar running its migration health-wait loop as `bash` reads `starting`, not
`unhealthy`, until it exec's the daemon. `existential-adhoc` disables this healthcheck
(`healthcheck: disable: true`) since it runs ephemeral one-shots, never the daemon.

---

## Setup

### Full setup (first run)
```bash
./existential.sh
```

1. Render `.env.exist.shared` → `.env.shared` (prompts for any `EXIST_CLI` values)
2. All services default to disabled. If none are enabled, the quest picker launches
   automatically so you can choose what to build (re-run with `./existential.sh quest`).
3. For every service with `EXIST_IS_<CATEGORY>_<SLUG>=true`, render its `*.exist.*`
   template files (e.g. `docker-compose.exist.yml` → `docker-compose.yml`). `automations/`
   is processed when `EXIST_IS_SERVICES_DECREE=true`. Disabled services are **skipped**
   so their secret/template files never land on disk.
4. For each enabled service with `exist.initial.sh`, run it (idempotent — scripts
   check for existing state and skip completed work). No sentinels.
5. Merge enabled services into a unified `docker-compose.yml` (and write the
   master `.env`) via the existential-adhoc container.
6. After `docker compose up -d`, each service's decree sidecar (where present) waits
   for `exist.test.sh` to pass, then runs `decree process` to execute any pending
   migrations in `<service>/decree/migrations/`.

### Targeted commands
```bash
./existential.sh --force        # Re-render existing files + re-run all initials
./existential.sh quest          # Pick what to build (interactive), then run full setup
# Run dispatch — general utilities (src/lib/<name>.sh):
./existential.sh run backup-config    # Configure rclone backup destination
./existential.sh run backup-restore   # Interactive DB, SQLite, or volume restore
./existential.sh run rclone           # Configure rclone remotes
./existential.sh run check-versions   # Compare pinned image tags against latest; add --update to apply

# Run dispatch — service-specific (<category>/<slug>/exist.<action>.sh):
./existential.sh run                       # List every available run action
./existential.sh run <slug>                # Run <slug>'s exist.initial.sh
./existential.sh run <slug> <action>       # Run <slug>'s exist.<action>.sh
# Examples:
./existential.sh run actual-budget setup   # Connect to budget server, save credentials
./existential.sh run ntfy setup            # Save ntfy access token
./existential.sh run ollama pull-models    # Pull configured Ollama models
./existential.sh run ollama benchmark      # Benchmark decode tok/s across context sizes (optional model arg)
./existential.sh run caddy public-domain   # Set up optional public domain with real HTTPS
./existential.sh run decree gmail-sync
./existential.sh run decree gmail-labels
./existential.sh run decree gmail-transactions-cron
./existential.sh run decree decree-ui

# Backups run inside per-service decree sidecars on their own cron schedule.
# Copy cron templates from <service>/decree/cron.example/ → decree/cron/ to activate.
# Edit each cron file's TARGETS / VOLUMES frontmatter to configure targets.
docker exec <svc>-decree decree run db-backup -- nightly     # Trigger db-backup now
docker exec <svc>-decree decree run volume-backup -- nightly # Trigger volume-backup now

./existential.sh test                    # Run all enabled-service exist.test.sh + src/test/*
./existential.sh run <slug> test         # Test one service (read-only validation)
./existential.sh validate                # Conventions + drift checks
./existential.sh validate conventions    # Slugs synced across compose/piHole/Caddy/dashy
./existential.sh validate drift          # What re-rendering would change
./existential.sh e2e                     # End-to-end: fresh clone → render → docker up → test → down (all e2e-able quests)
./existential.sh e2e automation          # E2E for quests matching a name/filename pattern
./existential.sh e2e ai finance          # E2E for specific quests (one pattern each)
```

### Manual service setup
```bash
cp services/foo/.env.exist services/foo/.env
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
| `EXIST_*` | Value of matching variable from root `.env.shared` |

An `EXIST_CLI` prompt can opt into a fallback by adding a comment immediately
above the line: `# DEFAULT_FROM: EXIST_FOO`. If the user enters blank,
the value of `EXIST_FOO` (already written earlier in the same file) is
used. Used today for `EXIST_PEER_HOST_IP` defaulting to `LOCAL_HOST_IP`.

---

## Env var naming convention

**Top-level (`.env.exist.shared`):**
- Every key starts with `EXIST_`. The legacy `EXIST_DEFAULT_*` and
  `EXIST_ENABLE_*` prefixes are no longer accepted.
- Service-enablement flags use `EXIST_IS_<CATEGORY>_<SLUG>=true|false`
  (e.g., `EXIST_IS_AI_HERMES`, `EXIST_IS_SERVICES_MEALIE`).
- Shared cross-service values live here and are referenced as `${EXIST_FOO}`
  in service compose files — no need to copy them into each service's `.env`.

**Per-service (`<cat>/<slug>/.env.exist`):**
- Every key starts with `<SLUG>_` (folder name uppercased; hyphens → underscores).
  `actual-budget` → `ACTUAL_BUDGET_`, `open-webui` → `OPEN_WEBUI_`.
- Image-required names (`MYSQL_USER`, `GF_*`, `LLM_BINDING`, etc.) get mapped
  in `docker-compose.exist.yml`: `MYSQL_USER: ${MEALIE_MYSQL_USER}`.
- Files copied wholesale from an upstream project that uses `env_file:` (e.g.,
  Immich, LightRAG) can opt out with a top-of-file marker:
  `# convention-exempt: upstream-env`.

Run `./existential.sh validate conventions` to check both rules.

---

## Volume convention

### Why `volumes/` exists

Docker named volumes are opaque: data lives in `/var/lib/docker/volumes/` with no hint
of what it contains, whether it matters, or whether anyone is backing it up. Worse, a
named volume is always initialised from the image's own directory on first mount —
preserving the image's internal UID — so a service that runs as uid 1000 on an NFS share
may silently fail on a plain named volume because the image initialised it as uid 10000.

The `volumes/` directory solves both problems:

- **Visibility.** Data lives at a predictable, inspectable path on the filesystem —
  `volumes/mealie_data/`, `volumes/hermes_agent_data/`, etc. — not buried in Docker's
  volume store.
- **Correct ownership.** A bind mount inherits the permissions of the host directory,
  which is created by the current user. No UID mismatch, no silent fallback.
- **Honest defaults.** When NFS is not configured, a service that declares a persistent
  volume gets a bind mount to `volumes/<name>/`, not a named volume that looks backed up
  but isn't. The presence of the directory in the repo signals "this data matters".
- **Uniform paths.** `volumes/<name>/` mirrors the NFS share naming exactly. Switching
  between NFS and local storage is a config change, not a data migration.
- **e2e parity.** The test harness gets the same bind-mount behaviour as a real install,
  so a passing e2e test actually reflects what a user without NFS would experience.

**"Why is there a `volumes/` directory in a code repo?"** Because the alternative is
invisible state. A `volumes/mealie_data/` directory makes it obvious that Mealie writes
persistent data that needs to survive container restarts and be included in backups.
Named volumes hide this. If you are confused by the directory, check whether the
corresponding service is enabled — if it isn't, the directory is empty and inert.

### Two classes of volume

**Persistent** (survives container removal, backed up by decree sidecars):
- Declared in the service template with `driver_opts: type: nfs`.
- With NFS (`EXIST_NFS_SERVER_ADDRESS` set): Docker mounts the NFS share directly.
- Without NFS (`EXIST_NFS_SERVER_ADDRESS` empty): `generate-compose.ts` converts these
  automatically to bind mounts pointing at `volumes/<name>/` in the repo root.
- A subdirectory `volumes/<name>/` with a committed `.gitkeep` must exist; actual data
  is gitignored. The same path is what decree sidecars mount for backups.
- Conventional name: `<service>_<purpose>_data` (snake_case), matching the trailing
  segment of `device:`. E.g., `mealie_data`, `hermes_agent_data`.
- Service compose files reference the NFS server via `${EXIST_NFS_SERVER_ADDRESS}` and
  `${EXIST_NFS_BASE_PATH}` directly — no per-service copy needed.

**Ephemeral** (cache, regen-able source, scratch — not backed up):
- Declared as plain named volumes (no `driver_opts`) in service compose templates.
- Live in Docker's volume store; recreated on `docker compose down -v`.
- Examples: `hermes_agent_src` (Python source, regen-able on image upgrade),
  `hermes_workspace_data` (file-browser scratch).

### Adding a persistent volume to a new service

1. Declare it in the service compose template with `driver_opts: type: nfs` (copy the
   pattern from any existing service).
2. `mkdir volumes/<name> && touch volumes/<name>/.gitkeep` and commit both.
3. Validation runs against the generated master `docker-compose.yml`, not the templates.

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
- **`.env.shared`** holds `EXIST_LOCAL_HOST_IP` (this machine) and
  `EXIST_PEER_HOST_IP` (the other machine; defaults to LOCAL).

**Container-to-container traffic → `http://<container>:<port>`** (Docker's
built-in service DNS on the `exist` network):

- Service env vars in `*/docker-compose.exist.yml` and `.env.exist` use
  this form (e.g., `OLLAMA_BASE_URL=http://ollama:11434`).
- Automation routines (`automations/shared_routines/*.sh`) and shared libs use this
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

Toggle services via `EXIST_IS_*=true/false` in `.env.shared`, then re-run setup:

```bash
./existential.sh          # render templates + run initials + regenerate compose
./existential.sh --force  # same, but re-renders already-existing files too
```

`src/generate-compose.ts` runs in the `existential-adhoc` container via `tsx`. It reads
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
- Routines: `automations/shared_routines/<name>.sh` + registered in each daemon's `config.yml`
- Cron jobs (main decree): `services/decree/decree/<name>.md`
- Cron jobs (service sidecars): `<category>/<slug>/decree/cron/<name>.md`
- Webhook endpoints: `services/decree/webhook/config.yml`
- Run commands via: `docker exec decree decree <command>`
- Backup commands via: `docker exec <service>-decree decree run db-backup`

### Shared routine registration convention

Decree auto-enables routines found in the local routines directory. Because all daemons
use `shared_routines` (a shared source directory via `routine_source`), routines default
to **disabled** unless explicitly listed in `shared_routines` in the config. The
`config.exist.yml` template is the whitelist — only listed routines are visible to that
daemon at all.

When you add a routine to `automations/shared_routines/`, add it to every `config.exist.yml`
that should have access to it. Set `enabled: true` for routines that should be on by
default for that daemon's purpose, `enabled: false` for routines that are available but
require the user to opt in. Any routine not listed is simply invisible to that daemon.

```yaml
# config.exist.yml (template — tracked)
shared_routines:
  volume-backup:
    enabled: true   # on by default — this sidecar exists to run backups
  new-routine:
    enabled: false  # available but opt-in
```

Which configs to update depends on the routine's purpose:
- **Backup routines** (`db-backup`, `volume-backup`) — add to every sidecar that owns
  a volume or database.
- **Notify / utility routines** — add to every daemon that might use them.
- **Main-decree-only routines** (AI workflows, gmail, telegram, etc.) — add only to
  `services/decree/decree/config.exist.yml`.

The rendered `config.yml` (gitignored) is where a user overrides what the template set.

### Cron routine setup convention

Every decree daemon has a paired `cron/` (active, gitignored) and `cron.example/`
(tracked templates) directory. The `.example_` suffix intentionally does **not**
match `*.exist.*`, so existential.sh never auto-renders these — they're manual.

To activate a cron template:

```bash
cp <service>/decree/cron.example/<name>.md <service>/decree/cron/<name>.md
docker compose restart <service>-decree
```

The active `cron/` is mounted into the daemon read-only; on restart, decree
parses the frontmatter (`cron:`, `routine:`, extra keys exposed as env vars
to the routine) and schedules accordingly. The `clean-runs` routine prunes
old run logs across all daemons (because all share `automations/runs/`).

---

## Testing Services

Every service ships an `exist.test.sh` that validates the service is fully operational
without changing any state. See "Service test scripts" above for the convention.

```bash
./existential.sh test                  # All enabled services + general src/test/*
./existential.sh run <slug> test     # One service — read-only validation
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
  and ship `exist.test.sh` with it. Add `exist.initial.sh` only if pre-startup filesystem
  setup is needed; add a decree migration if post-startup automated setup is needed.
- **Remove a service** — remove it from that section
- **Add or remove a script** in `src/` — update the src/ tree
- **Add or remove a Decree routine or cron file** — no change needed here; those are
  covered by the `/decree` command which reads the live files
- **Change a run command** (e.g. new `./existential.sh run <name>` subcommand or new quest) —
  update the Targeted commands section
- **Add a new top-level directory** — add it to the directory structure overview
- **Introduce a new convention** — add a dedicated section under the existing convention
  blocks (env var, NFS, container naming, networking, …). Conventions only work if
  they're written down.

Do not let CLAUDE.md describe things that no longer exist. If you notice a stale entry
while working on an unrelated task, fix it in the same commit.
