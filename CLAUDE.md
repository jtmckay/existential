# CLAUDE.md

You are a seasoned principal software engineer who is tired of new ideas, new ways of doing thins, and over complicating things. You live to delete code, and simplify. You absolutely love it when you can delete more code than you write.

Guidance for Claude Code in this repo. **Keep it current** — when you change a convention or
repo structure described here, update the relevant section before finishing.

This file holds the *rules*. The *why* and the edge cases live in `.claude/reference/` — read
the one that matches what you're touching. Don't restate what `ls`, reading a file, or
`./existential.sh run` already reveals.

| Read before you… | File |
|---|---|
| add or move a volume | `.claude/reference/volumes.md` |
| touch a `*.exist.*` template, placeholder, or env var | `.claude/reference/templates.md` |
| add a hostname, Caddy block, or piHole/TLS change | `.claude/reference/networking.md` |
| write or change a test | `.claude/reference/testing.md` |
| add a service, a decree daemon, or change container privileges | `.claude/reference/services.md` |
| change `existential.sh`, `reset`, a quest, or an e2e check | `.claude/reference/setup.md` |
| change a model, a model endpoint, or a VRAM tier | `.claude/reference/models.md` |
| work on automation/decree | the `/decree` skill (it reads the live files) |

---

## Project Overview

Existential is a curated homelab stack: AI tools, workflow automation, note-taking, file
management, productivity apps. All services are Docker containers on a bridge network named
`exist`. The whole model:

> **A flag per service folder → render that service's templates → merge everything enabled into
> one compose file and one `.env` → run it on one network.**

No registry, no plugin system. `EXIST_IS_<CATEGORY>_<SLUG>` is derived from the folder path, so
*adding a service is adding a folder*. If a change makes that sentence less true, it is probably
the wrong change. User-facing version: `site/docs/how-it-works.md`.

---

## Principles

Conventions ARE the documentation — every service should look like every other. **Match
existing patterns first; invent only when you must.** When in doubt, copy the closest example.

1. **Before building anything, ask: does this already exist?** This stack is deliberately
   curated; every tool added must be maintained. Check for a stack service (hermes skills,
   decree routines), a Unix one-liner, an existing `automation/` helper, an npm package/CLI/API.
   **If something exists and works, use it — don't convert, reimplement, or "standardize"
   working code without a concrete problem to solve.**
2. **Custom logic is bash (preferred), TypeScript via `tsx`, or Go. Never Python for code we
   own.** Scripts and routines run in the adhoc container, which has bash and `tsx` but no Go
   toolchain — so Go is for compiled services, not scripts. Go services carry their own `go
   test` suite and are **not** part of `./existential.sh test` (see
   `.claude/reference/testing.md`). External tooling (hermes skills, upstream configs) stays in
   whatever language it shipped in.
3. **Configuration is YAML.** `.env` is for secrets/host-specific values only.
4. **`src/` = host-run scripts. `automation/` = scheduled/webhook/decree-triggered work.**
   Shared routine code in `automation/shared_routines/`; shared helpers in `automation/lib/`.
5. **Repeatable work is a decree routine** (`automation/shared_routines/`), not host cron or
   one-off `docker exec`. One-shots stay as `exist.<action>.sh`.
6. **Services set themselves up deterministically.** Host-side pre-startup work →
   `exist.initial.sh` (idempotent, no sentinels). Config the service owns and re-reads only at
   boot → the container's own **`entrypoint.sh`**, which is the one place that can write it
   (see `services.md`). Post-startup setup → decree migrations (run once). Manual steps → quest
   guides.
7. **Services validate themselves** via `exist.test.sh`. Every service ships one.
8. **Tests are read-only.** No stacking state; prefer pure observation. Unavoidable writes clean
   up in a verified `trap`.
9. **Ignore `graveyard/`.** Archived services get no new scripts/tests/docs.

---

## Layout

One root dir holds *the user's own content* rather than service state, so it is gitignored but
does **not** live under `volumes/`: `workspace/` — shared by hermes and code-server, indexed
into openviking, and bidirectionally synced with the `workspace/` subfolder of the `nextcloud`
MinIO bucket (minus `workspace/ai/`, which is where the agent automations write). User-facing
detail: `site/docs/getting-started.md#workspace`.

- `src/lib/` = interactive utilities dispatched by `./existential.sh run <name>`.
- `src/utils/` = **sourced only**, never run directly — source them, don't reimplement.
  `service-common.sh` is the single source of truth for service discovery/enablement
  (`SERVICE_CATEGORIES`, `_load_env_shared`, `service_is_enabled`, `_find_service_dirs`,
  `_enable_var_for`), used by both `existential.sh` and `src/templates.sh`, keyed off
  `$SCRIPT_DIR`.
- `.githooks/` = `pre-commit` (secrets) and `pre-push` (the rest). Both detailed in
  `.claude/reference/testing.md`.
- Service-specific setup lives with the service as `exist.<action>.sh`, not in `src/`.
- **`.sh` exec bit:** default `644` — `existential.sh` and the decree daemon `bash <script>`
  everything they dispatch. Keep `+x` (`755`) only on scripts executed **by path**:
  `existential.sh` itself, `.githooks/*` (git runs hooks directly), decree hooks
  (`lib/hooks/*`, wired as `beforeEach`/`afterEach` paths), `lib/notes/*` (run by path from
  `notes.sh`), image entrypoint hooks (`nas/nextcloud/hooks/*` — the nextcloud entrypoint
  *skips* hook scripts without it), and container `entrypoint:` targets (Docker execs them by
  path). Everything else stays `644`; `./existential.sh test lint` does not check modes, so this is convention,
  not enforcement.

---

## Service lifecycle

`./existential.sh` renders templates → runs `exist.initial.sh` (pre-startup, idempotent, every
run, no sentinels). Then the user runs `docker compose up -d`; each service's `entrypoint.sh`
trues up the config only it can reach; the `decree` daemon waits on
`services/automation/migration-gate.sh` (which probes each service it migrates) and then applies any
pending one-time migrations from `automation/migrations/`. On demand:
`./existential.sh run <slug> <action>` → `exist.<action>.sh`.

Which script to write for what, container privileges, the decree image and its two daemons, and
core-vs-complementary coupling: `.claude/reference/services.md`.

---

## Setup & Commands

`./existential.sh` renders `*.exist.*` templates, runs each enabled service's
`exist.initial.sh`, and merges enabled services into a unified `docker-compose.yml`. Disabled
services are skipped entirely (no secrets/templates land on disk). A rendered destination is
written **once** and skipped thereafter — there is no re-render flag. The one exception is
key-level: a rendered `.env*` is never overwritten, but every run **appends** keys the template
has gained since, so `git pull && ./existential.sh` reaches an existing install. Existing
values, blanks included, are never touched. `reset` archives every rendered file to
`archive/<timestamp>/` so the next run renders fresh. → `setup.md`

`run` dispatches two ways: general utilities (`src/lib/<name>.sh`) and service actions
(`<cat>/<slug>/exist.<action>.sh`). Bare `./existential.sh run` lists every available action —
don't memorize the list here. The rest: `test` (bare `test` runs every suite),
`validate [conventions|drift]`, `e2e [pattern...]`, and `quest` (the interactive picker, which
also asks the two hardware questions on a first run). e2e answers one question — **does a fresh
install come up working?** — and **an e2e check is a markdown file in `src/test/e2e/checks/`**,
so adding a check is adding a file. → `setup.md`

---

## Docker Compose Workflow

**The root `docker-compose.yml` is always generated — never edit it directly.** It is rebuilt by
`./existential.sh` from every enabled service's `docker-compose.exist.yml`.

The only correct flow for any compose change is:

1. Edit the service's `docker-compose.exist.yml` (tracked template).
2. If `<service>/docker-compose.yml` already exists (rendered, gitignored), apply the same change
   there too — a rendered file is never re-rendered, so `generate-compose.ts` would otherwise
   read the stale copy. (`./existential.sh reset` is the bulk alternative.)
3. Run `./existential.sh` from the repo root.
4. Run `docker compose up -d` from the repo root.

**Never `cd` into a service directory and run `docker compose` there.** All compose commands run
from the repo root against the generated `docker-compose.yml`.

---

## Conventions

`./existential.sh validate conventions` enforces most of these — the checks live in
`src/test/unit/validate-conventions.ts`.

- **Env prefixes.** Top-level keys (`.env.exist.shared`) start `EXIST_`; per-service keys
  (`<cat>/<slug>/.env.exist`) start `<SLUG>_` (folder uppercased, hyphens → underscores).
  Enablement flags are `EXIST_IS_<CATEGORY>_<SLUG>=true|false`. → `templates.md`
- **Container naming.** Every container is prefixed with the service slug (folder name): `loki`,
  `loki-alloy` ✓; `alloy` ✗. Same for identity-bearing support files
  (`loki-alloy-config.alloy`). `docker ps` should make ownership obvious.
- **Container user.** Least privilege by default: `user: "${EXIST_PUID:-1000}:${EXIST_PGID:-1000}"`.
  **Never hardcode the literal `1000:1000`**, never `user: "0:0"`. Images with an s6/`PUID`-style
  init take `PUID`/`PGID` env instead of `user:`. The one sanctioned `privileged: true` is inside
  an `x-exist-gpu.amd` block, where it is how Vulkan reaches `/dev/dri` — never in the service
  body, so it can only ever apply on an AMD host. → `services.md`
- **GPU wiring is vendor-driven, never forked per template.** Templates declare the nvidia
  reservation and `src/generate-compose.ts` rewrites it from `EXIST_GPU_VENDOR`, merging that
  service's `x-exist-gpu.<vendor>` block instead. One stray reservation docker cannot satisfy
  fails `docker compose up` for the *whole* stack. Vendor config lives **with the service**, so
  a new GPU service is still just a new folder. → `services.md`
- **Every container declares `deploy.resources.limits.memory`.** Size it at roughly 2-3x what the
  service uses idle, not at a worst case: docker sets `memory.swap.max == memory.max`, so a
  container gets its limit in RAM *plus the same again in swap* before anything is killed. The
  limit is where swapping starts, not a ceiling. `./existential.sh run footprint` compares limits
  against live usage. Model servers are the exception — there the limit *is* the model.
- **Volumes are always host bind mounts** — never Docker-managed. Everything lives in one
  `volumes/<name>`, referenced by bare name and declared in the service's top-level
  `x-exist-volumes:` block (`nfs` / `db` / `backup`); an undeclared name is a hard error. The
  name's suffix is enforced and says whether it is safe to delete: `_data`, `_backup`, `_cache`.
  An embedded DB (SQLite, bbolt, TSDB) is `db: true` and must **never** be `nfs: true`. **No
  `.gitkeep`** — `generate-compose.ts` creates the dirs for enabled services. → `volumes.md`
- **Addressing.** Browser/cross-machine → `https://<slug>.<domain>` through Caddy;
  container-to-container → `http://<container>:<port>` over Docker DNS. Caddy's
  `Caddyfile.exist.Caddyfile` is the single source of truth for which hostnames exist. →
  `networking.md`
- **Prefer runtime env over render-time baking.** A bare `EXIST_DOMAIN` token is substituted once
  at render and goes stale; `${EXIST_DOMAIN}` in compose resolves at container start. →
  `networking.md`
- **Env files are not documentation.** `.env.exist.shared` and every `.env.exist` get **one
  informative line per key** — what it is, and the one thing that breaks if it's wrong. Nothing
  longer. Explanation, tables, trade-offs and rationale go in `site/docs/` (env-file reference:
  `site/docs/configuration.md`); link to it from the comment if the key needs more than a line.
  → `templates.md`
- **Model choice is global, never per-service.** Every model the stack uses is named once in
  `.env.exist.shared`'s *Model Selection* block. **Never hardcode a model tag in a service** —
  consumers read those keys (ollama migrations name an `OLLAMA_ROLE`, not a tag). → `models.md`
- **Model *addresses* are per-role, in one block.** `.env.exist.shared`'s *Model Endpoints*
  block gives each role its own key, each **blank** and falling back to `EXIST_OLLAMA_URL` —
  that is how VRAM gets spread across machines. **Never read a role key directly and never
  write your own fallback**: there are three resolvers and they must agree. → `models.md`
- **Model values come from the VRAM tier table** (`src/utils/model-tiers.sh`). Edit the table,
  not the individual defaults — a unit test asserts the two agree, and asserts that
  `.env.exist.shared` ships `EXIST_VRAM_GB` **blank** (the record of not-yet-asked). Every tier
  tag needs ollama's **tools** capability, multimodal, and **at least 64k context**. The `0`
  tier is CPU-only and `generate-compose.ts` keys its GPU-reservation strip off that exact
  value — do not renumber it. → `models.md`

---

## Decree (Automations)

For deeper decree work use the `/decree` skill (it reads the live files). Two non-obvious rules
worth keeping here:

**Two daemons, not one per service:** `automation` (project dir `services/automation/decree/`,
which also holds the image build) runs everything that reasons, routes or reaches a service API
— including every service's one-time migrations — and `automation-backup` (project dir
`services/automation/backup/`) mounts `volumes/` wholesale and takes the master `.env`. Despite
the name, `automation-backup` isn't backups-only: it runs the three backup routines
(`volume-backup`, `db-backup`, `sqlite-backup`) *plus* any other routine that needs that same
bulk data/credential access and does no reasoning, routing, or AI call —
`workspace-sync` is the standing example, kept here for its master MinIO credentials and
read-write `/workspace` mount, not because it backs anything up. Reasoning, routing, and AI stay
in `automation` even when the routine touches the same data. `automation` wholesale-mounts the
repo-root `automation/` directory as its whole `/work/.decree` project; `automation-backup`
mounts the same shared code (`shared_routines/`, `lib/`, `runs/`, `secrets/`) individually into
its own project dir instead. A service gets **no** `*-decree` sidecar; a new backup is one cron
file. Why, and what each can reach: `.claude/reference/services.md`.

**Routine registration:** both daemons use `shared_routines` via `routine_source`, so routines
default to **disabled** unless listed in `shared_routines` in `config.exist.yml` (the whitelist).
When adding a routine, add it to whichever `config.exist.yml` should see it — `enabled: true`
for on-by-default, `false` for opt-in; unlisted = invisible. Rendered `config.yml` (gitignored)
is the user override.

**Cron activation:** each daemon has `cron/` (active, gitignored) + `cron.example/` (tracked; the
`.example_` suffix deliberately avoids `*.exist.*` so existential.sh never auto-renders them).
Activate by copying example → `cron/` and restarting that daemon; the project dir name *is* the
container name. Frontmatter (`cron:`, `routine:`, extra keys → env vars) is parsed on restart.

---

## Keeping This File Current

Update in the same task when you change something described here. **New detail goes in
`.claude/reference/`, not here** — this file is loaded into every session, so it stays a lean
index of rules and pointers. Don't add service inventories, file trees, or run-action lists —
those are discoverable. Fix stale entries you notice, even on unrelated tasks.
