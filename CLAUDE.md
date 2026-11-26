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
| change `existential.sh`, `reset`, the plugin command, or an e2e check | `.claude/reference/setup.md` |
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

**Every decree machine the repo ships is in one place, `automation/plugins/`.** A plugin is a
file: `automation/plugins/<name>.md` is one **decree plugin file** (decree's `name`, `extends`,
`machine`, `scripts`, `cron`, `state`, `order`, `needs`) with existential's own keys beside them, always
`x-exist-<key>` (lib, handlers, endpoints), and its **`x-exist-project`** tag says which daemon
runs it: `automation`, `backup` (automation-backup) or `host` (a list when more than one does).
Each project's `.decree/plugins/` is written from these, and `decree install` installs them into
`.decree/machines/<name>/`; neither is committed, the repo's own `.decree` included. A plugin
carries its own cron and order files; one with no machine is lib others need (`model`, `pi`,
`agent`, `fleet`, a file processor). **A flow is not a file here: it is a row on
`site/docs/flows/index.md`**, the services and plugins one job turns on and what is left for a
person. decree's official plugins are `decree_*` (`decree_order`, `decree_ai`,
`decree_prune`, `decree_lease`...), which a plugin here `needs:` and decree adds, and which are
never edited: **to change one, a plugin here `extends:` it under its own name** and holds only
what it changes (`gpu_lease`, `lease_gpu`, `skill`, `repo_develop`, `repo_qa`); a `needs:` entry
`{<need>: <plugin>}` meets the base's need with another plugin. Never fork an official plugin's
scripts into a plugin here. All automation code lives in plugins: `automation/lib/` is only the
plugin system's own, and a project's `.decree/lib/` (ours: decree 0.6 has none) is that plus
its plugins' `x-exist-lib`.

**The repo is every plugin there is, none of it on. What is on is each project's own list**,
`.decree/plugins/.on` (never committed): the plugins a person turned on there, a new project
starting with `PLUGIN_DEFAULTS` (`automation/lib/plugin.sh`). `./existential.sh plugin on|off
<name>` edits the list of each project the plugin is tagged for and syncs it at once; each
`./existential.sh` installs into each project what its list has plus what that `needs:`, at the
checkout's version, so `git pull` reaches a running stack, and removes a repo plugin nothing on
needs. **The tag is a wall:** a project never installs a plugin not tagged for it, and nothing
`automation` can write (the workspace) decides or changes what `backup` or the host runs.

**Your own plugins are written in the workspace.** `workspace/.decree` is writable in every
container that mounts it (`automation`, code-server, Nextcloud, `automation-backup`): a machine of
your own is a plugin file in `workspace/.decree/plugins/<name>.md`, installed with `decree install
<name>` from there. `./existential.sh` installs the repo's plugins into the same folder and leaves
a plugin file it did not write alone. What the stack builds on its own (`develop` from a note,
another stack) is an **offer** in `workspace/ai/proposed/<name>.md`, which a person reads and
moves into `.decree/plugins/`; no machine installs. No code in a machine's `state/` (decree
0.6's rule: code is `scripts/`, from the plugin file); data a person edits lives in the store
(`workspace/.decree/store/<plugin>/`, a plugin's `state:`, which each machine's `state/` links
to). User-facing: `site/docs/plugins/offer-and-accept.md`. A config file that is yours (`handlers.yml`,
`decree-go-rest.yml`) ships as a `<name>.exist.<ext>` example and is copied to
its real name once. → `.claude/reference/decree.md`

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
   (see `services.md`). Post-startup setup → decree order files (run once). Manual steps → the
   flow's row on `site/docs/flows/index.md`, or the service's docs page.
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

- `.decree/` = the **host's** decree project, run by a decree daemon on the host. **Not part of
  Core:** nothing Core turns on is tagged for it, and `./existential.sh` leaves it alone until
  something is on in its list (`.decree/plugins/.on`). Host plugins like `pull_existential` and `report_host`, and the machines that develop this repo (`repo_develop` and
  `repo_qa`, extending `decree_develop` and `decree_qa`: host plugins too, off until turned
  on). Tracked there: only `machines/repo_develop/order/` (the repo's migrations, as order
  files), `machines/repo_develop/state/order.git.txt` (which ran) and `.gitignore`.
  `repo_develop` is `decree_develop` (implement → gate → fix → verify) whose gate is
  `.githooks/pre-push` and whose `conventions.md` is this file's rules.
  **Its order files are declarative**, as decree's `decree_order` plugin runs them: each is the desired
  state of one concern, so to change the repo you edit one and commit; `decree_order` runs an edited
  file again at the next daemon start (or `echo | decree emit --machine decree_order`), and
  `repo_develop`'s `commit` records it in `order.git.txt` with the work. Never hand-edit that
  record. A host plugin carries no `order:` of its own: that folder is the repo's.
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
  `.githooks/*` (git runs hooks directly), a plugin's decree scripts
  (decree installs one executable when it starts `#!`, and the sync does the
  same for a plugin's `x-exist-lib` file), image entrypoint hooks (`nas/nextcloud/hooks/*` — the nextcloud entrypoint
  *skips* hook scripts without it), and container `entrypoint:` targets (Docker execs them by
  path). Everything else stays `644`; `./existential.sh test lint` does not check modes, so this is convention,
  not enforcement.

---

## Service lifecycle

`./existential.sh` renders templates → runs `exist.initial.sh` (pre-startup, idempotent, every
run, no sentinels). Then the user runs `docker compose up -d`; each service's `entrypoint.sh`
trues up the config only it can reach; the `automation` decree daemon runs, at start, each
plugin's order files that have not run (decree's `decree_order` plugin), each waiting on its own
service in a first `wait_for_<service>` state. On demand:
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
**if the user says yes** (with no terminal, as under `pull_existential`, without asking). Every run then pulls and builds every enabled image (the decree image
when its build context changed) without touching running containers, so the next `up -d` gets
them. Every run also installs each decree project's plugins at this checkout's version. The
optional `pull_existential` plugin pulls, re-runs and `up -d`s on its own, `report_host`
reports the host to its controller, `boot_daemon` runs `.decree/boot.sh` once when that daemon
starts, `check_versions` says weekly which pinned images are behind, `update_ubuntu` patches an
Ubuntu host, and `lease_gpu` (a `decree_lease`) has a GPU box's llama.cpp, ComfyUI and TTS take
turns on its card; all six are host plugins (`x-exist-project: host`), run by a decree daemon in
the repo's own `.decree` that the host starts at boot, and `./existential.sh` says so until it does.
`reset` archives every rendered file to `archive/<timestamp>/` so the next run renders
fresh. → `setup.md`

`run` dispatches two ways: general utilities (`src/lib/<name>.sh`) and service actions
(`<cat>/<slug>/exist.<action>.sh`). Bare `./existential.sh run` lists every available action —
don't memorize the list here. The rest: `test` (bare `test` runs every suite),
`validate [conventions|drift]`, `e2e` (Core, from a fresh clone), `service [list|on|off]` (a
picker) and `plugin [list|on|off|sync|export]`. The
first bare run asks nothing: it builds Core (code-server, ntfy, automation, qmd, Firecrawl), makes
the login (`admin`, a generated password, printed once) and leaves one step, the model
(`EXIST_MODEL_URL`, `EXIST_MODEL_KEY`). Controller and worker are `run fleet controller|join`. A
host with neither docker nor podman is always a worker, set up with the host's own decree and
yq, so the host plugin sync is host code (bash 3.2). Only an email is asked, when an enabled
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
  the `host` label, the repo's own `.decree`), in docs, code, comments and messages alike.
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
- **Every notification names its ntfy topic** (`decree emit --machine notify --param
  ntfy_topic=<topic>`), one of the Topics table on `site/docs/services/ntfy.md`: `host` for the
  server's own news (Grafana, health, backups, updates; a plugin doing that work carries
  `x-exist-topic: host`, which routes its failed runs too), `decree`, `suggestions`, `digest`,
  `exist`. A new topic is a row there first; `test plugins` checks both ways.
- **Every container's log is capped** (json-file, 3 × 10 MB): `generate-compose.ts` writes
  it into each service, because docker never trims one. A template sets `logging:` only to
  differ; it stays `json-file`, which `loki-alloy` reads.
- **Volumes are always host bind mounts** — never Docker-managed. Everything lives in one
  `volumes/<name>`, referenced by bare name (optionally with a subpath into it,
  `workspace_data/notes`) and declared in the service's top-level `x-exist-volumes:` block
  (`nfs` / `db`); an undeclared name is a hard error. The name's suffix is enforced and
  says whether it is safe to delete: `_data`, `_share`, `_backup`, `_cache`. An embedded DB (SQLite, bbolt,
  TSDB) is `db: true` and must **never** be `nfs: true`. An `nfs: true` volume is the one
  exception to bind mounts: given `EXIST_NFS_ADDRESS` and its `EXIST_NFS_PATH_<VOLUME>`,
  Compose mounts it from the NAS, and nothing in the stack ever writes a folder there. **Anything gitignored is a volume** — a
  relative bind source is for tracked config only, never for state, however regenerable. **No
  `.gitkeep`** — `generate-compose.ts` creates the dirs for enabled services. → `volumes.md`
- **Addressing.** Core's two web apps → `https://<host>.<tailnet>.ts.net` (code-server) and
  `:8443` (ntfy) via `tailscale serve`, from ports published on `EXIST_CORE_BIND` (`127.0.0.1`
  while Tailscale serves them, else `0.0.0.0`, set every run); add-ons in a
  browser → `https://<slug>.<domain>` through Caddy, which ships off;
  container-to-container → `http://<container>:<port>` over Docker DNS; one whose service is
  off here → the controller's `https://<slug>.<domain>` (`resolveOffServices` in
  `generate-compose.ts`, ntfy → the controller's Loki). Caddy's
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
- **One model address; the fleet spreads models.** `EXIST_MODEL_URL` is this host's
  **OpenAI-compatible `/v1` base URL** (blank: no model yet), with `EXIST_MODEL_KEY` its key
  (blank: the fleet secret) and `EXIST_MODEL_CHAT` blank meaning the first model it lists; a
  hosted LLM, ollama, llama.cpp, Strata and the controller's `ai/model-gateway` all serve it;
  ollama-only steps (pull, unload, `/api/*`) run only when ollama is enabled. Decree scripts
  reach a model through `model_base` (lib/model.sh), which leases the host whose offer lists
  the model and falls back to `EXIST_MODEL_URL`: never add a per-role or per-service address.
  → `models.md`
- **Model values come from the VRAM tier table** (`src/utils/model-tiers.sh`). Edit the table,
  not the individual defaults — a unit test asserts the two agree, and asserts that
  `.env.exist.shared` ships `EXIST_VRAM_GB` **blank** (the record of not-yet-asked). Every tier
  tag needs ollama's **tools** capability, multimodal, and **at least 64k context**. The `0`
  tier is CPU-only and `generate-compose.ts` keys its GPU-reservation strip off that exact
  value — do not renumber it. → `models.md`

---

## Decree (Automations)

decree **0.6** (0.6.1): the `/decree` skill covers decree itself, and `.claude/reference/decree.md`
covers how existential uses it. The rules worth keeping here:

**Three decree projects, all installed from `automation/plugins/` by `x-exist-project` tag, not one per
service:** the host's (the repo's `.decree`, above), and two daemons in containers. `automation` (`workspace/.decree`) runs everything that reasons, routes or reaches a service API, including
every order file. `automation-backup` (`services/automation-backup/`, off by default: backups are not
Core) mounts `volumes/` wholesale, **the repo read-only**, and takes the master `.env`. It runs the backups plus
anything else that needs that bulk access and makes no AI call (`triage`, `notes_pull`,
`workspace_sync`).
**`/repo` is mounted there and nowhere else**: `automation` puts what it reads in front of a
model, so what that container can read is what a prompt injection can read. Both run
`automation/lib/`. `automation` mounts none of the repo but `automation/.env` and `/secrets`: not the
plugins, not any project's list. Nothing secret goes under `workspace/`: `.env` and `/secrets` stay in `automation/`. A service gets **no** `*-decree` sidecar; a new
backup is a line in a backup plugin's cron files.

**Automations never change your notes.** In `automation`, `workspace/notes/` is mounted
read-only: notes are what a person tells the stack to do, so no run, and no Claude a run calls,
can change them. What a machine makes goes to `workspace/ai/`. `develop` only offers what it
builds, in `ai/proposed/`.

**A plugin is the unit:** `automation/plugins/<name>.md`, one machine (one state until a run
shows the need for more) and its scripts, snake_case, with its `x-exist-project`. Change one live, then `./existential.sh
plugin export <name>` writes it back to commit, read from the most privileged project that runs
it (host, backup, automation), never from the workspace for a plugin another project runs. Params a message passes must be declared in the
machine's `data:`. Chaining is `decree emit` with `emits:` on the state, and `needs:` names what a
plugin emits to. A project has only the plugins it has on.

**AI is half of what decree is for, in two places.** *Conversation:* code-server ships
`claude`, `opencode` and `pi` for a person to drive, and the decree skill in the workspace is how a
conversation offers new machines (a plugin file in `.decree/plugins/`, installed with `decree install`). *Automations:* a machine's script calls AI itself, in one of
three ways, each a library plugin a machine `needs:`. `model` (`lib/model.sh`: `model_chat`,
`model_gate`) is one answer from the role's `/v1` URL. `pi` (`lib/pi.sh`: `pi_run`) is
[pi](https://pi.dev) with tools on that same chat model, nothing leaving the box; a department
(`store/agent_task/departments/<name>.yml`, yours, the shipped two written once from `agent_task`'s `state:`; *a
department is a file*) picks its tools and MCP servers, and `pi_configure` writes pi's provider
and servers in both the decree image's entrypoint and code-server's. `agent` (`lib/agent.sh`)
is Claude Code with tools, through
`ai` from decree's official `decree_ai` plugin, which the `agent` plugin needs.
`model` and `pi`, and `comfy`, lease a GPU another host offers through the `fleet` lib, asking
the controller where it is (→ `decree.md`, *Offers*).
`automation`'s image ships `claude`, signed in once per install. `develop` builds machines with
it, and the machines it builds call `agent`. A headless call runs in decree's `auto` mode
(`AUTOMATION_CLAUDE_PERMISSION_MODE`), kept from notes by the mount above.
Repo-editing belongs to a coding agent on the host, not to the stack.

**Cron activation:** a plugin carries its cron and order files (`cron:`, `order:`; its
`x-exist-examples` are inbox messages for reading, never installed), and decree installs them
into its machine's folder: a cron file once, then it is the project's to edit, and gone with the
plugin; an order file once, run by `order` at the daemon's start, and again only if edited.
There is no top-level cron folder (decree 0.6 reads only `machines/*/cron/`): a schedule of
your own is a plugin whose only key is `cron:` (each file naming its `machine:`), installed
like any other (`decree install --cron <name>` installs its cron files again after an edit). A backup is a line in
`volume_backup`'s, `db_backup`'s or `sqlite_backup`'s cron files, which list every service they
know and skip what is off here. The daemon rescans cron files every tick.

**Opt-in is the rule.** A new `automation` project starts with `PLUGIN_DEFAULTS`: `note_watch`,
`reconcile`, `service_health`, `pi` (code-server's agents need its lib), `file_advise` and
`you_were_here`, and nothing else; only the kernel (`PLUGIN_KERNEL`: `notify`, `decree_prune`
and, in `automation`, `skill`) is installed regardless. Anything new ships off, as a plugin a
person turns on with its row on the Flows page; never add a default, an always-installed
machine, or an example file to copy by hand.

**Gate:** `./existential.sh test decree` runs `decree check` on each project with every plugin
tagged for it installed and every template queued, then on each plugin alone with only its `needs:`.
`decree install` draws each machine's `graph.md`; none is committed.

---

## Keeping This File Current

Update in the same task when you change something described here. **New detail goes in
`.claude/reference/`, not here** — this file is loaded into every session, so it stays a lean
index of rules and pointers. Don't add service inventories, file trees, or run-action lists —
those are discoverable. Fix stale entries you notice, even on unrelated tasks.
