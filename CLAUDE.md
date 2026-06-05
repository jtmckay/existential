# CLAUDE.md

Guidance for Claude Code in this repo. **Keep it current** — when you change a convention
or repo structure described here, update the relevant section before finishing. Don't
restate what `ls`, reading a file, or `./existential.sh run` already reveals.

---

## Project Overview

Existential is a curated homelab stack: AI tools, workflow automation, note-taking, file
management, productivity apps. All services are Docker containers on a bridge network
named `exist`.

---

## Primary Goal: Don't Reinvent the Wheel

**Before building anything — script, routine, service, utility — ask: does this already
exist?** This stack is deliberately curated; every tool added must be maintained. Compose
existing pieces, don't accumulate. Check: a stack service (hermes skills, decree
routines), a Unix one-liner, an existing `automations/` helper, an npm package/CLI/API.

**If something exists and works, use it. Don't convert, reimplement, or "standardize"
working code without a concrete problem to solve.** Exception: scripts *we* author use
bash (preferred) or TypeScript/Node (`tsx`) — not Python. External tooling (hermes
skills, upstream configs) stays in whatever language it shipped in.

---

## Principles

Conventions ARE the documentation — every service should look like every other. **Match
existing patterns first; invent only when you must.** When in doubt, copy the closest
example.

1. **Custom logic is bash, then TypeScript** (via `tsx` in the adhoc container). Never
   Python for code we own.
2. **Configuration is YAML.** `.env` is for secrets/host-specific values only.
3. **`src/` = host-run scripts. `automations/` = scheduled/webhook/decree-triggered work.**
   Shared routine code in `automations/shared_routines/`; shared helpers in `automations/lib/`.
4. **Repeatable work is a decree routine** (`automations/shared_routines/`), not host cron or
   one-off `docker exec`. One-shots stay as `exist.<action>.sh`.
5. **Services set themselves up deterministically.** Pre-startup filesystem work →
   `exist.initial.sh` (idempotent, no sentinels). Post-startup setup → decree migrations
   (run once). Manual steps → quest guides.
6. **Services validate themselves** via `exist.test.sh` (see below).
7. **Tests are read-only.** No stacking state; prefer pure observation. Unavoidable writes
   clean up in a verified `trap`.
8. **Ignore `graveyard/`.** Archived services get no new scripts/tests/docs.

---

## Layout

Categories: `ai/` `services/` `nas/` `hosting/` (each holds slug-named service dirs).
Plus: `automations/` (shared decree code), `src/` (setup/utility scripts), `volumes/`
(persistent bind mounts when NFS unset), `decree/` (cloned source, read-only reference),
`site/` (Docusaurus docs), `graveyard/` (archived — leave alone).

- `src/lib/` = interactive utilities dispatched by `./existential.sh run <name>`.
- `src/utils/` = **sourced only**, never run directly — source them, don't reimplement.
  Includes `service-common.sh` (shared `SERVICE_CATEGORIES` + `_load_env_shared` /
  `service_is_enabled` / `_find_service_dirs` / `_enable_var_for`; the single source of
  truth used by both `existential.sh` and `src/templates.sh`, keyed off `$SCRIPT_DIR`).
- `src/test/` splits into `unit/` (no live services), `integration/` (live creds/containers),
  `e2e/` (full-stack harness). Per-service tests live with the service as `exist.test.sh`.
  **Every test mechanism has an opposite** — a test silently swallowing a failure is worse
  than no test. The opposites (all on the **host**, need git/bash, no adhoc; part of `test`
  (all) and run early in `pre-push`):
  - `no-tracked-secrets.sh` (`test secrets`) — asserts this public repo tracks no rendered secrets.
  - `guard-selftest.sh` (`test guards`) — plants secret-shaped fixtures in throwaway repos and
    asserts `pre-commit` **and** `no-tracked-secrets.sh` actually trip (incl. the `*.exist.*` /
    `*.example` exemptions). New secret-guard logic ⇒ add a fixture here.
  - `harness-selftest.sh` (`test harness`) — proves the *plumbing* surfaces failures: `run-all.sh`
    fails+names a failing suite, and `container-health.sh` (driven by a fake `docker`) trips on a
    bad container.
  - `test selfcheck` (adhoc) — runs every `unit/test-*.sh` with `TEST_SELFCHECK=1`, which fires a
    one-line canary (`[[ "${TEST_SELFCHECK:-}" == 1 ]] && _fail …`) each suite carries just before
    its tally; asserts each suite then exits non-zero. **Every unit suite must carry that canary.**
  - `unit/test-validators.sh` — opposite-tests the TS validators: builds violating fixture trees,
    asserts `validate-conventions`/`check-drift` exit non-zero (and pass on a clean tree).
- `.githooks/` (auto-installed via `core.hooksPath=.githooks` on `default`/`quest`):
  `pre-commit` blocks secrets from entering the public repo (lean/fast — the one
  irreversible failure); `pre-push` runs the host-side opposites first (`test guards`, `test
  harness` — cheap, no Docker, fail fast) then `test unit`, `test selfcheck`, and `validate
  conventions` (heavier, needs Docker — gated once per push, not per commit). Bypass either
  with `--no-verify`.
- Service-specific setup lives with the service as `exist.<action>.sh`, not in `src/`.
- **`.sh` exec bit:** default `644`. `existential.sh` and the decree daemon `bash <script>`
  everything they dispatch, so the bit is redundant there. Keep `+x` (`755`) only on scripts
  executed **by path**: `existential.sh` itself, `.githooks/*` (git runs hooks directly),
  decree hooks (`lib/hooks/*`, wired as `beforeEach`/`afterEach` paths), and `lib/notes/*`
  (run by path from `notes.sh`).

---

## Decree image & sidecars

The decree image is built **once** from `automations/Dockerfile` by `existential-adhoc`,
tagged `existential/decree:local`; main `decree` and every `*-decree` sidecar reference it
via `image:` (not rebuild). WORKDIR is `/work` (project at `/work/.decree`). Baked
healthcheck: `grep -q decree /proc/1/comm` with a long `start-period` (330s) so a sidecar
running as `bash` during its migration wait shows `starting`, not `unhealthy`. Adhoc
disables the healthcheck.

Each backup-eligible service ships a `decree/` subdir + a `<slug>-decree` sidecar that
mounts **only its own volumes** and receives **only its own DB creds** (no master `.env`).
All daemons share `automations/`'s `shared_routines/`, `lib/`, `runs/` via read-only mounts
(routines at `/work/.decree/shared_routines`), so logs from every daemon land in one audit
trail. Sidecar `decree/` dirs mirror the main daemon (`config.exist.yml` + `routine_source`,
`cron.example/`, gitignored runtime dirs).

---

## Service lifecycle scripts

```
./existential.sh run:
  1. templates.sh     Render *.exist.* → live files
  2. exist.initial.sh Pre-startup, idempotent, every run. No sentinels — check state, skip if done.
docker compose up -d  (user runs)
  3. exist.test.sh    Sidecar retries until this passes (service healthy)
  4. decree process   Runs pending one-time migrations from <service>/decree/migrations/
On demand:
  exist.<action>.sh   ./existential.sh run <slug> <action> — interactive/manual, documented as quest
  exist.test.sh       ./existential.sh run <slug> test — read-only validation
```

| Script | Write when… |
|---|---|
| `exist.initial.sh` | Files/dirs/system config needed before container start. Idempotent. |
| migration `migrations/<name>.md` | Post-startup setup (API calls, user creation, seeds). Runs once. |
| `exist.<action>.sh` | Interactive on-demand ops a user triggers. Document in a quest. |
| `exist.test.sh` | Always. Every service ships one. Also the sidecar health gate. |

Scripts self-elevate into `existential-adhoc` when they need its tooling (`if [[ -z
"$IN_CONTAINER" ]]; then exec docker compose run …`). Init order (`run_initials`):
`hosting → nas → ai → services`.

### exist.test.sh

Validates the service from its own perspective (container running, port listening, API
smoke, env vars, deps reachable) and prints copy-pasteable remediation on failure.

- **Read-only**, **service-scoped** (flag missing deps, don't recurse), **exit non-zero on
  failure**, **skip cleanly when disabled** (`EXIST_IS_<CAT>_<SLUG>` false → exit 0).
- In sidecar context (`DECREE_SIDECAR=true`), `skip_if_disabled` and `probe_caddy` are no-ops.
- Suggested output: `[<slug>] <check>  OK|FAIL` with `observed:`/`fix:` lines.

**Container-state gate** (`src/test/integration/container-health.sh`): adhoc has no docker
socket, so per-service tests can't see crash-looping/exited/unhealthy containers or
network-less daemons. This host-side gate asserts every container is `running`, not
restart-looping, not `unhealthy`. Wired into `./existential.sh test` (before adhoc run-all)
and `e2e.sh` (after `up -d --build`, fails the quest on trip). e2e always uses `--build` so
it never tests a stale image.

---

## Setup & Commands

`./existential.sh` renders `*.exist.*` templates, runs each enabled service's
`exist.initial.sh`, and merges enabled services into a unified `docker-compose.yml`. Disabled
services are skipped entirely (no secrets/templates land on disk). `--force` re-renders
existing files; `quest` launches the interactive picker first.

`run` dispatches two ways: general utilities (`src/lib/<name>.sh`, e.g. `backup-config`,
`rclone`, `check-versions`) and service actions (`<cat>/<slug>/exist.<action>.sh`). Bare
`./existential.sh run` lists every available action — don't memorize the list here.

`test [unit|integration|services]`, `validate [conventions|drift]`, and `e2e [pattern...]`
(fresh clone → render → up → test → down) round out the entry points.

---

## Conventions

### Placeholders (in `*.exist.*` templates)
`EXIST_CLI` prompts the user; `EXIST_24_CHAR_PASSWORD` / `EXIST_{32,64}_CHAR_HEX_KEY`
generate secrets; `EXIST_TIMESTAMP`, `EXIST_UUID`; bare `EXIST_*` pulls the matching var
from root `.env.shared`. An `EXIST_CLI` line can fall back to another var with a
`# DEFAULT_FROM: EXIST_FOO` comment directly above it (used if the user enters blank).

### Env var naming
- **Top-level** (`.env.exist.shared`): every key starts `EXIST_`. Enablement flags:
  `EXIST_IS_<CATEGORY>_<SLUG>=true|false`. Shared cross-service values live here, referenced
  as `${EXIST_FOO}` in compose files.
- **Per-service** (`<cat>/<slug>/.env.exist`): every key starts `<SLUG>_` (folder uppercased,
  hyphens → underscores). Image-required names get mapped in compose
  (`MYSQL_USER: ${MEALIE_MYSQL_USER}`). Wholesale upstream env files opt out with top-of-file
  `# convention-exempt: upstream-env`.
- `./existential.sh validate conventions` checks both.

### Volumes
Docker named volumes are opaque and re-init from the image (wrong UID on NFS). `volumes/`
gives visible, inspectable, correctly-owned bind mounts.
- **Persistent** (backed up by sidecars): declared with `driver_opts: type: nfs`. With NFS
  set → mounted directly; without → `generate-compose.ts` converts to bind mounts at
  `volumes/<name>/`. Needs a committed `volumes/<name>/.gitkeep`. Name: `<service>_<purpose>_data`.
- **Ephemeral** (cache/scratch): plain named volumes, recreated on `down -v`.

### Container user & privileges
Least privilege is the default. An app container gets `user: "1000:1000"` (matches the host
user, so bind-mount files stay deletable without root) **unless it structurally needs root** —
in which case say why in a comment next to the omission (see hermes-agent's s6 note).
**Pick the right mechanism, not always `user:`:** images with an s6/`PUID`-style init (it starts
as root then drops) break under `user:` — set their `PUID`/`PGID` env to `1000` instead (lowcoder
does this). Use plain `user:` only for images that tolerate an arbitrary uid. Root is
expected for: privileged-port binders that can't take a cap (use `cap_add` over `privileged:
true` when possible — Caddy uses `cap_add: [NET_BIND_SERVICE]`), pihole (NET_ADMIN), portainer
(docker.sock), GPU/supervisor images (ollama, comfyui), multi-process app images managed by an
internal supervisor (appsmith, lowcoder, nextcloud), and images caching into `/root` (whisper, mcp).
The `*-decree` backup sidecars run as `user: "1000:1000"` like everything else — the volume data
they tar is `1000`-owned by the `volumes/` convention, so they need no extra privilege. **DB/cache
images** (postgres, mariadb, mongo, redis) also run `user: "1000:1000"`, but the data volume
must be owned by `1000` first — pinning `user:` on a dir already initialized under the image's
old service uid breaks startup until the volume is `chown`-ed. Never use `user: "0:0"`.

### Container naming
Every container is prefixed with the service slug (folder name): `loki`, `loki-promtail` ✓;
`promtail` ✗. Same for identity-bearing support files (`loki-promtail-config.yaml`).
`docker ps` should make ownership obvious. Validated by `validate conventions`.

### Networking
- **Browser / cross-machine → `https://<slug>.internal`**: piHole holds a record per slug
  (active line → `EXIST_LOCAL_HOST_IP`, commented PEER alternative); Caddy fronts each slug
  (`tls internal`, reverse-proxies `<container>:<port>`); Dashy links navigable slugs.
- **Container-to-container → `http://<container>:<port>`** (Docker service DNS). Use this in
  service env vars and routine fallbacks (`${X_URL:-http://service:port}`) — faster, no TLS,
  no CA trust needed.

A new service slug appears in three convention files (piHole, Caddy, Dashy if navigable);
cross-service env refs stay on Docker DNS. `validate conventions` verifies sync.

---

## Decree (Automations)

For deeper decree work use the `/decree` skill (it reads the live files). Two non-obvious
rules worth keeping here:

**Routine registration:** all daemons use `shared_routines` via `routine_source`, so routines
default to **disabled** unless listed in `shared_routines` in `config.exist.yml` (the
whitelist). When adding a routine, add it to every `config.exist.yml` that should see it —
`enabled: true` for on-by-default, `false` for opt-in; unlisted = invisible. Rendered
`config.yml` (gitignored) is the user override.

**Cron activation:** each daemon has `cron/` (active, gitignored) + `cron.example/` (tracked;
the `.example_` suffix deliberately avoids `*.exist.*` so existential.sh never auto-renders
them). Activate by copying example → `cron/` and restarting the daemon. Active `cron/` is
mounted read-only; frontmatter (`cron:`, `routine:`, extra keys → env vars) parsed on restart.

---

## Keeping This File Current

Update in the same task when you change something described here: a convention (add a
dedicated section), the lifecycle/test model, the decree image/sidecar setup, or a
command's dispatch behavior. Don't add service inventories, file trees, or run-action lists
— those are discoverable. Fix stale entries you notice, even on unrelated tasks.
