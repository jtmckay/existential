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
| change `existential.sh`, `reset`, a flow, or an e2e check | `.claude/reference/setup.md` |
| change a model, a model endpoint, or a VRAM tier | `.claude/reference/models.md` |
| work on automation/decree | the `/decree` skill, then `.claude/reference/decree.md` |
| change the homepage, `README.md`'s opening, or `site/docs/intro.md`'s opening | `.claude/reference/audience.md` |

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

**A plugin is a file.** `automation/plugins/<name>.md` is one decree machine with its scripts,
lib, endpoints and schedule. **A flow is a plugin with no machine**, in
`automation/plugins/flows/<name>.md`: one curated thing the stack does (`name`, `tagline`, the
services it turns on, the plugins and flows it `needs:`, its crons and migrations, and what is
left for a person), or lib others need (`model`, `pi`, `agent`, a file processor). One name space
across both folders. All automation code lives in plugins: `automation/lib/` is only the plugin
system's own, and a project's `.decree/lib/` is what its installed plugins put there.

**What is on is one file per project**, `.decree/plugins.yml` (`on:`, never committed), written
the first time from that project's `plugins.exist.yml`, which is what every install starts with.
`./existential.sh flow on|off <name>` edits it (and asks before turning on each service a flow needs); each
`./existential.sh` installs exactly what it lists plus what that `needs:`, at the checkout's
version, so `git pull` reaches a running stack. A file that is yours to edit ships as a
`<name>.exist.<ext>` example and is copied to its real name once. → `.claude/reference/decree.md`

---

## Principles

Conventions ARE the documentation — every service should look like every other. **Match
existing patterns first; invent only when you must.** When in doubt, copy the closest example.

1. **Before building anything, ask: does this already exist?** This stack is deliberately
   curated; every tool added must be maintained. Check for a stack service (pi departments,
   decree machines), a Unix one-liner, an existing `automation/` helper, an npm package/CLI/API.
   **If something exists and works, use it — don't convert, reimplement, or "standardize"
   working code without a concrete problem to solve.**
2. **Custom logic is bash (preferred), TypeScript via `tsx`, or Go. Never Python for code we
   own.** Scripts run in the adhoc or decree container, which has bash and `tsx` but no Go
   toolchain — so Go is for compiled services, not scripts. Go services carry their own `go
   test` suite and are **not** part of `./existential.sh test` (see
   `.claude/reference/testing.md`). External tooling (pi packages, upstream configs) stays in
   whatever language it shipped in. **Bash that runs on the host** (`existential.sh`, what it
   sources, `exist.initial.sh`) **runs on a Mac too**: bash 3.2 and BSD tools, checked by
   `./existential.sh test host`.
3. **Configuration is YAML.** `.env` is for secrets/host-specific values only.
4. **`src/` = host-run scripts. `automation/` = scheduled/webhook/decree-triggered work.**
   decree machines and every line of their code are plugins in `automation/plugins/`.
5. **Repeatable work is a decree machine** (a plugin in `automation/plugins/`), not host cron or
   one-off `docker exec`. One-shots stay as `exist.<action>.sh`.
6. **Services set themselves up deterministically.** Host-side pre-startup work →
   `exist.initial.sh` (idempotent, no sentinels). Config the service owns and re-reads only at
   boot → the container's own **`entrypoint.sh`**, which is the one place that can write it
   (see `services.md`). Post-startup setup → decree migrations (run once). Manual steps → the
   flow's body, or the service's docs page.
7. **Services validate themselves** via `exist.test.sh`. Every service ships one.
8. **Tests are read-only.** No stacking state; prefer pure observation. Unavoidable writes clean
   up in a verified `trap`.
9. **Docs describe the repo as it is.** A change that makes `README.md`, `site/docs/` or the
    homepage untrue updates them in the same change; a checkable doc claim gets a check.
    Every service folder has one docs page, which names it in `service: <cat>/<slug>`
    frontmatter, and `README.md`/`intro.md` list Core under `## What Core installs`; both are
    enforced by `validate conventions`.
10. **Long-running processes outside compose run in a named tmux session** via the `tmx`
    pattern (`tmx -d <name> <cmd>`: start only if not already running; `tmx <name>` to
    re-attach). "Is it running?" is `tmux has-session -t =<name>` — never a pidfile. → `services.md`

---

## Layout

The user's own content is the `workspace_data` volume — one tree mounted by nextcloud (as a
Local external storage the desktop client syncs), code-server and decree, and searched
by qmd (read-only; `.gitignore`d and hidden paths never indexed). **Every change in the workspace is seen** (`automation/lib/file-handlers.ts`, in
`automation`), but only a handler in `workspace/.decree/handlers.yml` turns one into a run, and a
`.gitignore`'d path or anything in `.git/` never does. The loop break is the handlers' patterns:
an automation writes where its own handler does not match (agent output in `workspace/ai/`).
Nextcloud's file events are an optional second path. User-facing detail:
`site/docs/decree/file-handlers.md`.

- `.decree/` = the decree project for *developing this repo* on the host (`develop`, `infra`,
  `qa`), not part of the stack and never a plugin project. `host/.decree` (gitignored) is the
  host's own project, for host plugins like `update`. `develop` is implement → gate, and its gate is `.githooks/pre-push`.
  **Its migrations are declarative, overriding the decree skill's "never edit a migration":**
  each one is the desired state of one concern, so to change the repo you edit the migration,
  commit, then `echo | decree emit --machine reconcile && decree process`. `reconcile`
  re-runs every processed migration that differs from its copy in `.decree/applied/`, which
  `develop` writes on success. Never hand-edit `applied/`.
- `src/lib/` = interactive utilities dispatched by `./existential.sh run <name>`.
- `src/utils/` = **sourced only**, never run directly — source them, don't reimplement.
  `service-common.sh` is the single source of truth for service discovery/enablement
  (`SERVICE_CATEGORIES`, `_load_env_shared`, `service_is_enabled`, `_find_service_dirs`,
  `_enable_var_for`), used by both `existential.sh` and `src/templates.sh`, keyed off
  `$SCRIPT_DIR`. `rendered-paths.sh` is the same idea for the inverse question — which
  `*.exist.*` template renders INTO a given path — and is what both secret guards use to decide
  a file is rendered and must never be tracked.
- `.githooks/` = `pre-commit` (secrets) and `pre-push` (the rest), mirrored by
  `.github/workflows/ci.yml`, which runs the same gates on push and PR. The hook is the fast
  local copy and is bypassable; CI is not. **Add a gate to both.** Detailed in
  `.claude/reference/testing.md`.
- Service-specific setup lives with the service as `exist.<action>.sh`, not in `src/`.
- **`.sh` exec bit:** default `644` — `existential.sh` `bash <script>`s everything it
  dispatches. Keep `+x` (`755`) only on scripts executed **by path**: `existential.sh` itself,
  `.githooks/*` (git runs hooks directly), the plugin system's decree scripts
  (`automation/scripts/*` — `decree check` refuses one without it; a plugin's are made `755` when
  it is installed, and so is a plugin `lib:` file that starts with `#!`), image entrypoint hooks (`nas/nextcloud/hooks/*` — the nextcloud entrypoint
  *skips* hook scripts without it), and container `entrypoint:` targets (Docker execs them by
  path). Everything else stays `644`; `./existential.sh test lint` does not check modes, so this is convention,
  not enforcement.

---

## Service lifecycle

`./existential.sh` renders templates → runs `exist.initial.sh` (pre-startup, idempotent, every
run, no sentinels). Then the user runs `docker compose up -d`; each service's `entrypoint.sh`
trues up the config only it can reach; the `automation` decree daemon runs any pending one-time
migrations from `workspace/.decree/migrations/`, each waiting on its own service in a first
`wait_for_<service>` state. On demand:
`./existential.sh run <slug> <action>` → `exist.<action>.sh`.

Which script to write for what, container privileges, the decree image and its two daemons, and
core-vs-complementary coupling: `.claude/reference/services.md`.

---

## Setup & Commands

`./existential.sh` renders `*.exist.*` templates, runs each enabled service's
`exist.initial.sh`, and merges enabled services into a unified `docker-compose.yml`. Disabled
services are skipped entirely (no secrets/templates land on disk). A rendered destination is
written **once** and skipped thereafter — there is no re-render flag. Two exceptions reach an
existing install on `git pull && ./existential.sh`: a rendered `.env*` gets every key the
template has gained **appended** (existing values, blanks included, never touched), and a
rendered compose file whose service `image:` differs from its template's is listed and updated
**if the user says yes**. Every run then pulls and builds every enabled image (the decree image
when its build context changed) without touching running containers, so the next `up -d` gets
them. Every run also installs each decree project's plugins at this checkout's version. The
optional `auto-update` flow pulls, re-runs and `up -d`s on its own, and the optional `worker` flow
reports the host to its controller, and the optional `on-boot` flow runs `host/boot.sh` once
when that daemon starts; all three are host flows, run by a decree daemon in `host/.decree`
that the host starts at boot, and `./existential.sh` says so until it does.
`reset` archives every rendered file to `archive/<timestamp>/` so the next run renders
fresh. → `setup.md`

`run` dispatches two ways: general utilities (`src/lib/<name>.sh`) and service actions
(`<cat>/<slug>/exist.<action>.sh`). Bare `./existential.sh run` lists every available action —
don't memorize the list here. The rest: `test` (bare `test` runs every suite),
`validate [conventions|drift]`, `e2e [pattern...]`, and `flow`/`service [list|on|off]` (pickers). The
first bare run asks one thing: Core (the default), controller (Core, reporting the others), worker
(no services; reports to a controller) or nothing. It is asked on the host, before the image is
built: a worker never builds it, and is set up with the host's own decree and yq, so the host
plugin sync is host code (bash 3.2). A host with neither docker nor podman is always a worker. A login is asked when an enabled
service first uses one; the hardware questions
(`src/lib/models.sh`) wait for the first enabled service that reserves a GPU. e2e answers one question — **does a fresh
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
   read the stale copy. An `image:` change alone is offered by `./existential.sh`.
   (`./existential.sh reset` is the bulk alternative.)
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
- **"Machine" means a decree machine.** A computer is a **host** (`<host>.<tailnet>.ts.net`,
  the `host` label, `host/.decree`), in docs, code, comments and messages alike.
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
- **Telemetry ships off.** Every service turns off upstream telemetry, usage reporting and error
  reporting with the project's own setting; no setting upstream → one line on its docs page.
  → `services.md`
- **Every container declares `deploy.resources.limits.memory`.** Size it at roughly 2-3x what the
  service uses idle, not at a worst case: docker sets `memory.swap.max == memory.max`, so a
  container gets its limit in RAM *plus the same again in swap* before anything is killed. The
  limit is where swapping starts, not a ceiling. `./existential.sh run footprint` compares limits
  against live usage. Model servers are the exception — there the limit *is* the model.
- **Volumes are always host bind mounts** — never Docker-managed. Everything lives in one
  `volumes/<name>`, referenced by bare name (optionally with a subpath into it,
  `workspace_data/notes`) and declared in the service's top-level `x-exist-volumes:` block
  (`nfs` / `db` / `backup`); an undeclared name is a hard error. The name's suffix is enforced and
  says whether it is safe to delete: `_data`, `_share`, `_backup`, `_cache`. An embedded DB (SQLite, bbolt,
  TSDB) is `db: true` and must **never** be `nfs: true`. An `nfs: true` volume is the one
  exception to bind mounts: given `EXIST_NFS_ADDRESS` and its `EXIST_NFS_PATH_<VOLUME>`,
  Compose mounts it from the NAS, and nothing in the stack ever writes a folder there. **Anything gitignored is a volume** — a
  relative bind source is for tracked config only, never for state, however regenerable. **No
  `.gitkeep`** — `generate-compose.ts` creates the dirs for enabled services. → `volumes.md`
- **Addressing.** Core's two web apps → `https://<host>.<tailnet>.ts.net` (code-server) and
  `:8443` (ntfy) via `tailscale serve`, from ports published on `127.0.0.1` only; add-ons in a
  browser → `https://<slug>.<domain>` through Caddy, which ships off;
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
  block gives each role its own key, each **blank** and falling back to `EXIST_MODEL_URL` —
  that is how VRAM gets spread across machines. Every value is an **OpenAI-compatible `/v1`
  base URL**, so ollama and llama.cpp both serve it; ollama-only steps (pull, unload,
  `/api/*`) run only when ollama is enabled. **Never read a role key directly and never write
  your own fallback**: there are three resolvers and they must agree. → `models.md`
- **Model values come from the VRAM tier table** (`src/utils/model-tiers.sh`). Edit the table,
  not the individual defaults — a unit test asserts the two agree, and asserts that
  `.env.exist.shared` ships `EXIST_VRAM_GB` **blank** (the record of not-yet-asked). Every tier
  tag needs ollama's **tools** capability, multimodal, and **at least 64k context**. The `0`
  tier is CPU-only and `generate-compose.ts` keys its GPU-reservation strip off that exact
  value — do not renumber it. → `models.md`

---

## Decree (Automations)

decree **0.5**: the `/decree` skill covers decree itself, and `.claude/reference/decree.md`
covers how existential uses it. The rules worth keeping here:

**Two daemons, each its own decree project, not one per service:** `automation` (`workspace/.decree`,
its plugins installed from the repo's `automation/plugins/`) runs everything that reasons, routes or reaches a service API, including
every migration. `automation-backup` (`services/automation-backup/`, off by default: backups are not
Core) mounts `volumes/` wholesale, **the repo read-only**, and takes the master `.env`. It runs the backups plus
anything else that needs that bulk access and makes no AI call (`triage`, `notes_pull`,
`workspace_sync`).
**`/repo` is mounted there and nowhere else**: `automation` puts what it reads in front of a
model, so what that container can read is what a prompt injection can read. Both run
`automation/lib/`, and each installs its machines from `automation/plugins/`. Nothing secret goes under `workspace/`: `.env` and `/secrets` stay in `automation/`. A service gets **no** `*-decree` sidecar; a new
backup is one cron file.

**Automations never change your notes.** In `automation`, `workspace/notes/` is mounted
read-only: notes are what a person tells the stack to do, so no run, and no Claude a run calls,
can change them. What a machine makes goes to `workspace/ai/`. Machines stay writable there,
because `develop` builds the automations a person accepts.

**A plugin is the unit:** `automation/plugins/<name>.md`, one machine (one state until a run
shows the need for more) and its scripts, snake_case. Change one live, then `./existential.sh run
plugin export <name>` writes it back to commit. Params a message passes must be declared in the
machine's `data:`. Chaining is `decree emit` with `emits:` on the state, and `needs:` names what a
plugin emits to. A project has only the plugins it has on.

**AI is half of what decree is for, in two places.** *Conversation:* code-server ships
`claude`, `opencode` and `pi` for a person to drive, and the decree skill in the workspace is how a
conversation makes new machines. *Automations:* a machine's script calls AI itself, in one of
three ways, each a library plugin a machine `needs:`. `model` (`lib/model.sh`: `model_chat`,
`model_gate`) is one answer from the role's `/v1` URL. `pi` (`lib/pi.sh`: `pi_run`) is
[pi](https://pi.dev) with tools on that same chat model, nothing leaving the box; a department
(`lib/departments/<name>.yml`, yours, the shipped two copied once from their `.exist.yml`; *a
department is a file*) picks its tools and MCP servers, and `pi_configure` writes pi's provider
and servers in both the decree image's entrypoint and code-server's. `agent` (`lib/agent.sh`)
is Claude Code with tools, through
`lib/ai.sh`, which is decree's own `ai` helper, unedited (`test decree` diffs it).
`automation`'s image ships `claude`, signed in once per install. `develop` builds machines with
it, and the machines it builds call `agent`. A headless call runs in decree's `auto` mode
(`AUTOMATION_CLAUDE_PERMISSION_MODE`), kept from notes by the mount above.
Repo-editing belongs to a coding agent on the host, not to the stack.

**Cron activation:** each project has its own `cron/` (active, not in git). A plugin carries its
crons and migrations (`cron:`, `migrations:`; a flow's `examples:` are inbox messages for
reading, never installed) and they go in and out with it; a migration is written once, after
every machine is in, and never again once it has run. `automation-backup`'s backup crons are in
`services/automation-backup/cron.example/`, copied by hand. The daemon rescans `cron/` every tick.

**Gate:** `./existential.sh test decree` runs `decree check` on both projects with every plugin
installed and every template queued, then on each plugin alone with only its `needs:`. The daemon
draws the graphs; none is committed.

---

## Keeping This File Current

Update in the same task when you change something described here. **New detail goes in
`.claude/reference/`, not here** — this file is loaded into every session, so it stays a lean
index of rules and pointers. Don't add service inventories, file trees, or run-action lists —
those are discoverable. Fix stale entries you notice, even on unrelated tasks.
