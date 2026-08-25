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
bash (preferred) or TypeScript/Node (`tsx`) — not Python; a long-running network
service we own may instead be Go (see Principle 1). External tooling (hermes skills,
upstream configs) stays in whatever language it shipped in.

---

## Principles

Conventions ARE the documentation — every service should look like every other. **Match
existing patterns first; invent only when you must.** When in doubt, copy the closest
example.

1. **Custom logic is bash, then TypeScript** (via `tsx` in the adhoc container). Never
   Python for code we own. **Go is allowed for one narrow case**: a long-running network
   service that should not depend on another image's runtime — it compiles to a static
   binary on `distroless`, so the container carries no interpreter or package tree.
   `services/decree/webhook/` is the only such service today. Go is not an option for
   scripts, routines, or anything the adhoc container can already run; a port to Go needs
   a parity harness proving it matches what it replaces, distilled into a golden-file suite
   once the port lands (see `webhook/main_test.go`) — the harness itself is scaffolding and
   goes away with the implementation it was diffing against.
   Go services carry their own `go test` suite (`webhook/main_test.go`) — adhoc has no Go
   toolchain, so it is **not** part of `./existential.sh test`; run it from the service
   dir, or in a container: `docker run --rm -v "$PWD":/src -w /src golang:1.26.5-alpine3.23 go test ./...`.
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

## What this stack actually is

Keep the whole model in view, because every convention below exists to serve it:

> **A flag per service folder → render that service's templates → merge everything enabled
> into one compose file and one `.env` → run it on one network.**

No registry, no plugin system. `EXIST_IS_<CATEGORY>_<SLUG>` is derived from the folder path,
so *adding a service is adding a folder*. If a change makes that sentence less true, it is
probably the wrong change. User-facing version: `site/docs/how-it-works.md`.

### Core vs complementary services

A service is **core** if something reaches it by bare container name over the `exist` bridge.
It is **complementary** if it is reached over a URL/protocol you could point anywhere (rclone
remote, S3 endpoint, DNS), or if nothing in the stack talks to it at all.

Complementary today: **NAS** (nextcloud, minio, collabora, redis — the core reaches these via
rclone remotes and the S3 API; `redis` serves only nextcloud), **immich** (nothing references
it), **homeassistant** (nothing references it either, and it is often bound to the host with
the USB radios plugged in), **pihole** (LAN DNS), **monitoring**
(grafana/loki/prometheus/uptime-kuma — they scrape, nothing depends on them).

A Caddy block and a Dashy tile do **not** make a service core — those are ingress and
navigation, and every complementary service has them. The test is a bare container name in
another service's config or env.

They all still join `exist` by default, which is fine on one host. The rule is about *not
adding new coupling*: **never introduce a bare-container-name dependency from the core stack
into a complementary service.** Reach it by configurable endpoint so it can move to another
machine — the recommended shape is three stacks (NAS / core / standalone immich + pihole).
When adding a service, decide which side it is on and wire it accordingly.

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

**`decree-webhook` is the exception** — it does *not* use this image. It is a static Go
binary (`services/decree/webhook/`) on `distroless`, built by compose from its own
`Dockerfile` rather than by `existential-adhoc`, and shares nothing with the daemon but
the inbox bind mount. Because distroless ships no shell, curl or wget, its healthcheck is
the binary probing itself (`/webhook -healthcheck`). Its `README.md` documents the
config-driven route table and the behaviours that differ from a plain JSON endpoint — read
it before changing anything in `webhook/`.

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

`test [secrets|guards|harness|selfcheck|unit|integration|services]` (bare `test` runs them
all), `validate [conventions|drift]`, and `e2e [pattern...]` (fresh clone → render → up →
test → down) round out the entry points.

---

## Conventions

### Placeholders (in `*.exist.*` templates)
`EXIST_CLI` prompts the user; `EXIST_24_CHAR_PASSWORD` / `EXIST_32_CHAR_HEX_KEY` generate
secrets; bare `EXIST_*` pulls the matching var from root `.env.shared`. An `EXIST_CLI` line
can fall back to another var with a `# DEFAULT_FROM: EXIST_FOO` comment directly above it
(used if the user enters blank). Add a new generator only when a template actually needs
it — three unused ones (`EXIST_64_CHAR_HEX_KEY`, `EXIST_UUID`, `EXIST_TIMESTAMP`) were
carried for nothing and removed.

`EXIST_NIP_DOMAIN` renders `<EXIST_LOCAL_HOST_IP with dots→dashes>.nip.io` — public
wildcard DNS that maps the name back to that IP, so `<slug>.<domain>` resolves on every
LAN device with no pihole and no `/etc/hosts`. It is the `EXIST_DOMAIN` default. Resolved
**after** the `EXIST_CLI` pass, so `EXIST_LOCAL_HOST_IP` must appear *above* it in the
template; falls back to `x.internal` when no valid IPv4 is set. pihole stays supported and
becomes a pure upgrade (it answers the same wildcard locally, dropping the internet-DNS
dependency); `.internal` domains still require it, which `_warn_if_no_gateway` checks.

### Always-rendered files

`templates.sh` renders a destination **once** and skips it thereafter (that's what preserves
user edits and prompted answers). `_ALWAYS_RENDER` in `src/templates.sh` is the carve-out: a
short list of destinations regenerated on **every** run, `--force` or not.

**A file only qualifies when its render is a pure function of (template + `.env.shared`)** —
no secrets, no `EXIST_CLI`. Otherwise re-running loses information: a prompt would re-ask
every run, and a regenerated secret would rotate out from under whatever already consumed it.
`_assert_always_render_safe` enforces this and hard-fails the render, so the list can't
silently go wrong. The `.env` never-overwrite guard is checked *first* and still wins.

Use it when an app reads a static config file it can't env-substitute, so a value like
`EXIST_DOMAIN` would otherwise be baked once and go stale. `services/dashy/dashy-conf.yml`
is the only entry today.

Three things come with it:

- **A `DO NOT EDIT` header** is stamped on the output naming the template. `check-drift.ts`
  keys off that exact marker string (`isGenerated`) to skip these files rather than keeping
  its own copy of the list — keep the two in sync.
- **The user opts out by flipping `# EXIST_KEEP: false` to `true`** in that header
  (`_render_opted_out`). The file is then theirs permanently: never regenerated, and
  `--force` won't touch it either. That is the whole customisation story — there is no
  override file and no merge engine. The toggle is a **comment**, so it stays valid in
  whatever format the destination is (a bare token would break the YAML dashy parses), and
  only the first 20 lines are inspected so the same words in the body mean nothing.
- **Write in place, never rename.** These files can be *single-file* bind mounts
  (dashy-conf.yml is), and `mv`/rename swaps the inode and detaches the running container's
  mount. `printf > "$dst"` truncates in place, which is why the archive-then-rename pattern
  `generate-compose.ts` uses for the root compose file must **not** be copied here.

If the app can read env, do that instead — see **Prefer runtime env over render-time baking**.

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
**We never use Docker-managed volumes** — they're opaque and re-init from the image (wrong
UID on NFS). Every volume is a **host bind mount**: visible, inspectable, correctly-owned.
Templates declare bind mounts **directly** — there is no top-level `volumes:` block and no
`materializeBindMounts` rewrite. Consolidation stays minimal: `generate-compose.ts`'s generic
`adjustVolume` only fixes the relative path (prepends the service dir, normalises to repo
root) — `../../<dir>/<name>` → `./<dir>/<name>`, the same handling every bind mount gets, for
**any** top-level dir. The generated `docker-compose.yml` has no `volumes:` block and `docker
volume ls` stays empty; `validate conventions` enforces this (no top-level volumes, no bare
named refs).

**Three tiers, picked by "is this backup-worthy?" and "is it NFS-safe?"** (name volumes
`<service>_<purpose>_data`):

| Tier | Form in template | NFS? | Backed up? | For |
|---|---|---|---|---|
| **1 — User data** | `- ${EXIST_NFS_HOST_MOUNT:-./volumes}/<name>:/path` | yes | yes (sidecar) | bulk files/blobs/media/attachments — NFS-safe |
| **2 — Live DB** | `- ../../volumes_local/<name>:/path` | **never** | yes — sidecar writes a safe archive into `volumes/<name>_backup/` | postgres, mariadb, mongo, embedded SQLite/bbolt/TSDB worth keeping |
| **3 — Ephemeral** | `- ./<dir>:/path` (in the service dir, gitignored) | no | **no sidecar** | caches, downloaded models, scratch, transient state |

Decision rule: **local-required AND backup-worthy → tier 2; local-required but throwaway →
tier 3; NFS-safe and backup-worthy → tier 1.** An embedded database (mmap, `flock`, SQLite
WAL — prometheus TSDB, bbolt, mongo) **must never** be tier 1: NFS corrupts or cripples it.

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

**Every** bind dir gets a committed `.gitkeep` so it exists on a fresh clone and Docker
doesn't root-create it (wrong owner): tier 1 `volumes/<name>/.gitkeep` (incl. each
`<name>_backup`), tier 2 `volumes_local/<name>/.gitkeep`, and tier 3 `<service>/<dir>/.gitkeep`
inside the service folder. Tier-3 `.gitkeep` is **force-added** past the gitignore — the dir's
*contents* are gitignored (not backup-worthy), but the empty dir is tracked (same pattern as
chatterbox's `logs/`, `outputs/`). Moving a service between tiers is a one-time **host** data
move (`mv volumes/<name> volumes_local/<name>`), called out in the migration note — never done
to live data automatically.

### Container user & privileges
Least privilege is the default. An app container runs as the **host** user
(`user: "${EXIST_PUID:-1000}:${EXIST_PGID:-1000}"`), so bind-mount files stay deletable
without root **unless it structurally needs root** — in which case say why in a comment next
to the omission (see hermes-agent's s6 note). **Never hardcode the literal `1000:1000`** —
always the `${EXIST_PUID:-1000}:${EXIST_PGID:-1000}` form (enforced by `validate
conventions`). `EXIST_PUID`/`EXIST_PGID` are auto-detected from the host (`id -u`/`id -g`) by
`existential.sh`'s `_ensure_host_ids`, written into `.env.shared`, and default to `1000` when
absent — so the stack works for a user who isn't `1000:1000` (LDAP, a second account, a
server) without any config.

**Pick the right mechanism, not always `user:`:** images with an s6/`PUID`-style init (it
starts as root then drops) break under `user:` — set their `PUID`/`PGID` (or `UID`/`GID`,
`HERMES_UID`/`GID`, …) **env** to `${EXIST_PUID:-1000}`/`${EXIST_PGID:-1000}` instead
(lowcoder, open-webui, hermes-agent do this). Use plain `user:` only for images that tolerate
an arbitrary uid. Root is expected for: privileged-port binders that can't take a cap (use
`cap_add` over `privileged: true` when possible — Caddy uses `cap_add: [NET_BIND_SERVICE]`),
pihole (NET_ADMIN), portainer (docker.sock), GPU/supervisor images (ollama, comfyui),
multi-process app images managed by an internal supervisor (appsmith, lowcoder, nextcloud),
and images caching into `/root` (whisperx, mcp). The `*-decree` backup sidecars run as the
host user like everything else — the volume data they tar is host-owned by the `volumes/`
convention, so they need no extra privilege. **DB/cache images** (postgres, mariadb, mongo,
redis) also run as the host user, but the data volume must be owned by that uid first —
pinning `user:` on a dir already initialized under the image's old service uid breaks startup
until the volume is `chown`-ed. Never use `user: "0:0"`.

### Container naming
Every container is prefixed with the service slug (folder name): `loki`, `loki-promtail` ✓;
`promtail` ✗. Same for identity-bearing support files (`loki-promtail-config.yaml`).
`docker ps` should make ownership obvious. Validated by `validate conventions`.

### Networking
The hostname suffix is `EXIST_DOMAIN`, defaulting to `EXIST_NIP_DOMAIN` →
`<lan-ip-with-dashes>.nip.io`, which public wildcard DNS resolves back to that IP — so
`<slug>.<domain>` works on every LAN device with **no piHole and no `/etc/hosts`**. Set it to
`x.internal` (piHole required, fully offline, and a second stack can take `y.internal`) or to
a domain you own. **Caddy's `Caddyfile.exist.Caddyfile` is the single source of truth for
which `<slug>.<domain>` hostnames exist** — `validate conventions` keys off it.

**DNS and TLS are independent choices.** piHole swaps public DNS for local (removing the
internet dependency); a real cert removes the trust step. Neither requires the other, and the
combination — owned domain + piHole + a DNS-01 wildcard cert — needs no public A record and
no inbound connectivity. See `site/docs/how-it-works.md`.

- **Browser / cross-machine → `https://<slug>.<domain>`**: when piHole is enabled it resolves
  the *whole* domain with **one wildcard record** (`FTLCONF_misc_dnsmasq_lines: address=/${EXIST_DOMAIN}/${EXIST_LOCAL_HOST_IP}`)
  — no per-slug DNS entries. Caddy fronts each slug (stable pinned `*.<domain>` cert via
  `import internal_tls` — **not** `tls internal`; minted once by caddy's `exist.initial.sh` into
  `hosting/caddy/certs/`, so trust survives reboots and `caddy_data` wipes), reverse-proxies
  `<container>:<port>`; Dashy links navigable slugs.
- **Container-to-container → `http://<container>:<port>`** (Docker service DNS). Use this in
  service env vars and routine fallbacks (`${X_URL:-http://service:port}`) — faster, no TLS,
  no CA trust needed.

Adding a service only touches **Caddy** (and Dashy if navigable) — piHole's wildcard already
covers it. `validate conventions` verifies Dashy/Caddy stay in sync and the wildcard record exists.

**Prefer runtime env over render-time baking.** A bare `EXIST_DOMAIN` token is substituted
*once*, when the file is rendered — and `templates.sh` skips files that already exist, so the
value goes stale. Resolve it at container start instead, which makes swapping domains a
one-line edit in `.env.shared`. (Where the app genuinely can't read env, the fallback is to
make the file always-render — see **Always-rendered files** below — but runtime env is still
the first choice: it needs no re-render at all.)

```yaml
# in docker-compose.exist.yml — derived from EXIST_DOMAIN, per-service override preserved
- CADDY_DOMAIN=${CADDY_DOMAIN:-$EXIST_DOMAIN}
- NTFY_BASE_URL=${NTFY_BASE_URL:-https://ntfy.$EXIST_DOMAIN}
```

Compose's `${VAR:-$OTHER}` chaining is verified to work. Where an app reads a config *file*,
check whether it also accepts env — ntfy maps every `server.yml` key to `NTFY_<KEY>` and env
wins, so its base-url lives in compose. Caddy reads `{$CADDY_DOMAIN}` from its container env,
so the Caddyfile never bakes a domain either.

**`EXIST_DOMAIN` form by file type:**
- compose `*.exist.yml` → `${EXIST_DOMAIN}` / `${SLUG_VAR:-…$EXIST_DOMAIN}` — **preferred**.
- rendered non-compose → bare `EXIST_DOMAIN` (render-substituted). **Last resort**, only when
  the app cannot read env. `dashy-conf.exist.yml` is the remaining case (Dashy reads a static
  `conf.yml` and does no substitution of its own); it is in `_ALWAYS_RENDER`, so a domain
  change propagates on the next plain `./existential.sh`. Note the bare-token sed rewrites
  **prose too** — don't name the variable in that file's comments or the name is replaced
  with its value.
- `.example` swap-ins (`Caddyfile.frontdoor.example`) → `{$EXIST_DOMAIN}` (Caddy expands from its
  container env). Never put `{$EXIST_DOMAIN}` in a rendered file — the bare-token sed would corrupt it.

**Peer mode (Caddy + piHole on a separate front-door host):** the front-door runs a tiny static
`Caddyfile.frontdoor.example` (copied to the live `Caddyfile`) that wildcard-forwards every
`<slug>.<domain>` to `EXIST_PEER_HOST_IP`, where a *second* Caddy runs the normal rendered
Caddyfile and routes to containers over Docker DNS. No per-slug peer config, no host-port
deconfliction — the front-door never changes as services are added.

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

## Docker Compose Workflow

**The root `docker-compose.yml` is always generated — never edit it directly.** It is
rebuilt by `./existential.sh` from every enabled service's `docker-compose.exist.yml`.

The only correct flow for any compose change is:
1. Edit the service's `docker-compose.exist.yml` (tracked template).
2. If `<service>/docker-compose.yml` already exists (rendered, gitignored), apply the
   same change there too — `./existential.sh` without `--force` won't re-render it, so
   `generate-compose.ts` would read the stale copy.
3. Run `./existential.sh` from the repo root (no `--force` — that re-prompts `EXIST_*`
   placeholders and is only needed when adding new secrets/vars to a template).
4. Run `docker compose up -d` from the repo root.

**Never `cd` into a service directory and run `docker compose` there.** All compose
commands run from the repo root against the generated `docker-compose.yml`.

---

## Keeping This File Current

Update in the same task when you change something described here: a convention (add a
dedicated section), the lifecycle/test model, the decree image/sidecar setup, or a
command's dispatch behavior. Don't add service inventories, file trees, or run-action lists
— those are discoverable. Fix stale entries you notice, even on unrelated tasks.
