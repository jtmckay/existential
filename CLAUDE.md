# CLAUDE.md

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
| add a service, sidecar, or change container privileges | `.claude/reference/services.md` |
| work on automations/decree | the `/decree` skill (it reads the live files) |

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
   decree routines), a Unix one-liner, an existing `automations/` helper, an npm package/CLI/API.
   **If something exists and works, use it — don't convert, reimplement, or "standardize"
   working code without a concrete problem to solve.**
2. **Custom logic is bash (preferred), TypeScript via `tsx`, or Go. Never Python for code we
   own.** Scripts and routines run in the adhoc container, which has bash and `tsx` but no Go
   toolchain — so Go is for compiled services, not scripts. Go services carry their own `go
   test` suite and are **not** part of `./existential.sh test` (see
   `.claude/reference/testing.md`). External tooling (hermes skills, upstream configs) stays in
   whatever language it shipped in.
3. **Configuration is YAML.** `.env` is for secrets/host-specific values only.
4. **`src/` = host-run scripts. `automations/` = scheduled/webhook/decree-triggered work.**
   Shared routine code in `automations/shared_routines/`; shared helpers in `automations/lib/`.
5. **Repeatable work is a decree routine** (`automations/shared_routines/`), not host cron or
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

Categories: `ai/` `services/` `nas/` `hosting/` (each holds slug-named service dirs). Plus:
`automations/` (shared decree code), `src/` (setup/utility scripts), `volumes/` (every persistent
bind mount; gitignored, created per enabled service), `decree/` (cloned source, read-only reference), `site/` (Docusaurus
docs), `graveyard/` (archived — leave alone). One root dir holds *the user's own content* rather
than service state, so it is gitignored but does **not** live under `volumes/`: `workspace/`
— shared by hermes and code-server, indexed into openviking, and synced to MinIO (minus
`workspace/ai/`, which is where the agent automations write).

- `src/lib/` = interactive utilities dispatched by `./existential.sh run <name>`.
- `src/utils/` = **sourced only**, never run directly — source them, don't reimplement.
  `service-common.sh` is the single source of truth for service discovery/enablement
  (`SERVICE_CATEGORIES`, `_load_env_shared`, `service_is_enabled`, `_find_service_dirs`,
  `_enable_var_for`), used by both `existential.sh` and `src/templates.sh`, keyed off
  `$SCRIPT_DIR`.
- `src/test/` = `unit/` + `integration/` + `e2e/`; `.githooks/` = `pre-commit` (secrets) and
  `pre-push` (the rest). Both detailed in `.claude/reference/testing.md`.
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
trues up the config only it can reach; the sidecar retries
`exist.test.sh` until it passes, and decree applies any pending one-time migrations from
`<service>/decree/migrations/`. On demand: `./existential.sh run <slug> <action>` →
`exist.<action>.sh`.

Which script to write for what, container privileges, the decree image/sidecars, and
core-vs-complementary coupling: `.claude/reference/services.md`.

---

## Setup & Commands

`./existential.sh` renders `*.exist.*` templates, runs each enabled service's
`exist.initial.sh`, and merges enabled services into a unified `docker-compose.yml`. Disabled
services are skipped entirely (no secrets/templates land on disk). A rendered destination is
written **once** and skipped thereafter — there is no re-render flag. The one exception is
key-level, not file-level: a rendered `.env*` is still never overwritten, but every run appends
keys the template has gained since (`_reconcile_env_keys` in `src/templates.sh`), so
`git pull && ./existential.sh` reaches an existing install. It is append-only — existing values,
blanks included, are never touched. `reset` archives every
rendered file to `archive/<timestamp>/` (paths preserved, gitignored, restore with `cp -r
archive/<stamp>/. .`) so the next run renders fresh; it never touches `volumes/` beyond
offering to delete the `*_cache` ones. It archives the generated `docker-compose.yml` too, so it first offers
to `docker compose down` a stack that is still up (host-side — `reset` itself runs in
adhoc, which has no docker socket). `quest` launches the interactive picker first. On a first run — nothing enabled beyond the
shipped defaults, which `_has_any_enabled` checks against `.env.exist.shared` rather than by
counting `true`s — quest asks two hardware questions and then leads with a single **Core, or no
thanks** choice (`src/quests/00-core.md`) instead of forty service checkboxes; declining falls
through to the full picker. The hardware questions are **GPU vendor first**
(`src/utils/gpu-vendor.sh` → `EXIST_GPU_VENDOR`), then VRAM (`src/utils/model-tiers.sh` →
`EXIST_VRAM_GB`); answering *No GPU* sets `EXIST_VRAM_GB=0` itself and **skips** the VRAM
question, so the VRAM picker is always asked with `--gpu-only`. `EXIST_GPU_VENDOR` records that
the pair was asked, so they are never re-asked; `run models` is the way back and re-asks both.

A quest is a markdown file in `src/quests/`: YAML frontmatter for the data (`name`, `tagline`,
`e2e`, `services`, `copies`), the body for the guide — the same shape as decree's cron and
migration files. It is read by `yq` in `quest.sh` (`qmeta` / `qbody`), NOT by decree, so decree's
"extra keys become env vars" contract does not apply. Everything that reads a quest must scope
itself to the frontmatter; the body is free-form prose.

`run` dispatches two ways: general utilities (`src/lib/<name>.sh`) and service actions
(`<cat>/<slug>/exist.<action>.sh`). Bare `./existential.sh run` lists every available action —
don't memorize the list here. The rest: `test [lint|secrets|guards|harness|selfcheck|unit|integration|services]`
(bare `test` runs them all), `validate [conventions|drift]`, and `e2e [pattern...]` (fresh clone
→ render → up → test → down).

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
  `loki-promtail` ✓; `promtail` ✗. Same for identity-bearing support files
  (`loki-promtail-config.yaml`). `docker ps` should make ownership obvious.
- **Container user.** Least privilege by default: `user: "${EXIST_PUID:-1000}:${EXIST_PGID:-1000}"`.
  **Never hardcode the literal `1000:1000`**, never `user: "0:0"`. Images with an s6/`PUID`-style
  init take `PUID`/`PGID` env instead of `user:`. The one sanctioned `privileged: true` is inside
  an `x-exist-gpu.amd` block, where it is how Vulkan reaches `/dev/dri` — never in the service
  body, so it can only ever apply on an AMD host. → `services.md`
- **GPU wiring is vendor-driven, never forked per template.** Templates declare the nvidia
  reservation (correct for the majority) and `src/generate-compose.ts` rewrites it from
  `EXIST_GPU_VENDOR`: `nvidia` is a no-op, `amd`/`none`/`external` strip the reservation — docker refuses to
  create a container whose device driver it cannot satisfy, so one stray reservation takes
  `docker compose up` down for the *whole* stack — and merge that service's `x-exist-gpu.<vendor>`
  block instead. Vendor config lives **with the service**, so a new GPU service is still just a
  new folder. A blank `EXIST_GPU_VENDOR` falls back to the old `EXIST_VRAM_GB == 0` meaning, which
  is what pre-vendor installs already assumed. → `services.md`
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
  `.env.exist.shared`'s *Model Selection* block (`EXIST_MODEL_CHAT`, `_CHAT_NUM_CTX`, `_EXTRACT`,
  `_EMBED`, `_EMBED_DIM`, `_VISION`, `_STT`, `_STT_LANGUAGE`, `_TTS_VOICE`). Consumers read those:
  ollama migrations name an `OLLAMA_ROLE` (not a tag), honcho renders `config.toml` from them, and
  the wyoming services take them as compose env. **Never hardcode a model tag in a service.**
- **Model *addresses* are per-role, in one block.** `.env.exist.shared`'s *Model Endpoints*
  block gives each role its own key (`EXIST_OLLAMA_URL_CHAT`, `_EXTRACT`, `_EMBED`, `_VISION`),
  each **blank** and falling back to `EXIST_OLLAMA_URL` — that is how VRAM gets spread across
  machines. **Never read a role key directly and never write your own fallback**: scripts source
  `src/utils/model-endpoints.sh` and call `endpoint_for <role>`; rendered templates write the
  bare token (`EXIST_OLLAMA_URL_EMBED`), which `src/templates.sh` resolves before substitution;
  compose files use `${EXIST_OLLAMA_URL_<ROLE>:-${EXIST_OLLAMA_URL:-http://ollama:11434}}`.
  Roles share `ollama-pull`'s `OLLAMA_ROLE` vocabulary so a model is pulled to the machine that
  serves it. Adding a role means touching all three resolvers —
  `src/test/unit/test-model-endpoints.sh` asserts they agree. STT/TTS get **no keys**: the
  wyoming services are CPU-only, so there is no VRAM to spread, and Home Assistant is told
  where they live in its own UI.
- **Model values come from the VRAM tier table** (`src/utils/model-tiers.sh`). Quest asks how
  much VRAM the machine has on first run (after the GPU vendor question, and only when the answer
  was not *No GPU*), `./existential.sh run models` re-asks later, and
  `.env.exist.shared` ships the default tier's *model* values (8 GB) but ships `EXIST_VRAM_GB`
  **blank** — that blankness is the record of not-yet-asked, and quest's picker fires only while
  it is empty, so shipping a value there makes the question unreachable. Edit the table, not the
  individual defaults — a unit test asserts the two agree, and asserts the blank. Every tier tag
  must have ollama's **tools** capability (hermes cannot act without it), be multimodal (so
  images reuse the resident model), and carry **at least 64k context** — hermes requires 64,000
  tokens and ollama truncates silently below it. On the small tiers that KV cache spills into
  system RAM, which is a speed cost, not a correctness one, so no tier is cut to meet the floor.
  The `0` tier is CPU-only and `generate-compose.ts` keys its
  GPU-reservation strip off that exact value — do not renumber it.

---

## Decree (Automations)

For deeper decree work use the `/decree` skill (it reads the live files). Two non-obvious rules
worth keeping here:

**Routine registration:** all daemons use `shared_routines` via `routine_source`, so routines
default to **disabled** unless listed in `shared_routines` in `config.exist.yml` (the whitelist).
When adding a routine, add it to every `config.exist.yml` that should see it — `enabled: true`
for on-by-default, `false` for opt-in; unlisted = invisible. Rendered `config.yml` (gitignored)
is the user override.

**Cron activation:** each daemon has `cron/` (active, gitignored) + `cron.example/` (tracked; the
`.example_` suffix deliberately avoids `*.exist.*` so existential.sh never auto-renders them).
Activate by copying example → `cron/` and restarting the daemon. Active `cron/` is mounted
read-only; frontmatter (`cron:`, `routine:`, extra keys → env vars) parsed on restart.

---

## Keeping This File Current

Update in the same task when you change something described here. **New detail goes in
`.claude/reference/`, not here** — this file is loaded into every session, so it stays a lean
index of rules and pointers. Don't add service inventories, file trees, or run-action lists —
those are discoverable. Fix stale entries you notice, even on unrelated tasks.
