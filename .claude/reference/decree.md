# decree in existential

decree itself — messages, machines, scripts, `decree check`, `emit`, `status` — is
the `/decree` skill (`.claude/skills/decree/`, written by `decree skill --ai claude`;
regenerate it on a version bump, never hand-edit it). This file is only what
existential adds on top. Both daemons run decree **0.5.0**, pinned in
`services/automation/decree/Dockerfile`; the webhook image bundles the same version.

## Two projects

| | `automation` | `automation-backup` |
|---|---|---|
| project (`/work/.decree`) | `workspace/.decree` (`volumes/workspace_data/.decree`) | `services/automation-backup/` |
| machines, scripts | the plugin system (`automation/machines/`, `scripts/`), plus the plugins its `plugins.yml` has on | `notify`, plus the plugins its `plugins.yml` has on, mounted read-only |
| lib | the plugin system's `automation/lib/`, plus its installed plugins' lib | the same, mounted read-only |
| what is on | `workspace/.decree/plugins.yml`, from `automation/plugins.exist.yml` | `services/automation-backup/plugins.yml`, rendered from its `plugins.exist.yml` |
| crons, migrations | each plugin's own (`cron:`, `migrations:`), in and out with it | its plugins' crons, plus `cron.example/`, copied by hand |
| runs | everything that reasons, routes, or calls a service API | backups, `triage`, `notes_pull`, `workspace_sync`: bulk mounts and master credentials, no AI |

Each project has its own `inbox/`, `runs/`, `store/`, `cron/` and `processed.md`.
The seeded `.gitignore` keeps `workspace/.decree`'s run state (runs, store, inbox,
attention, logs) from syncing; everything else there syncs, and `graph/` is drawn by the
entrypoint whenever a machine changes; nothing in the repo is a graph. A machine both run
(`notify`, `clean_runs`) is one definition, installed into both.
**`/repo` is mounted only into `automation-backup`**: `automation` hands what it
reads to a model, so what it can read is what a prompt injection can read.

## Plugins

**A plugin is a file**: `automation/plugins/<name>.md`, everything in its frontmatter (`chart`,
`scripts`, `lib`, `cron`, `migrations`, `endpoints`, `needs`; `automation/lib/automations/plugin.sh`
says what each is). With no `chart` it is a **flow**, in `automation/plugins/flows/<name>.md`:
one curated thing the stack does (`name`, `tagline`, `docs`, `services`, `needs`, `e2e`, then
`cron`, `migrations`, `examples` and a body of what is left for a person), or, without a tagline,
lib others need (`model`, `agent` with decree's `ai.sh`, `pi` with `departments/`, `firecrawl`,
`rss`, the file processors `ocr`, `transcribe`, `agent_handoff`). One name space across both
folders (validate conventions). Plugins are the only place automation code lives; the installed
copies are never committed. Every decree project installs from that one folder: `automation`
(`workspace/.decree`), `automation-backup`, and `host` (`host/.decree`, gitignored, for what runs
on the host itself: `update`).

- **What is on is one file per project**: `.decree/plugins.yml` (`on:`, `auto_update`), written
  the first time from the project's `plugins.exist.yml` (`automation/plugins.exist.yml`,
  `automation/plugins.host.exist.yml`, `services/automation-backup/plugins.exist.yml`), which
  is what every install starts with. An install from before it keeps what it had: `plugin.sh
  seed` turns on each flow whose cron or migration is already there and drops `flows-off`.
  A project has exactly what `on:` lists plus everything that `needs:`, so a flow another
  flow that is on needs stays on.
- **`./existential.sh flow`** is the picker over flows with a tagline (`src/flows.sh`): `on`
  asks, per service, to turn on each that its flows need and is off (`services:`, unless the GPU
  answer forbids one; no answer is no) and adds
  it to `plugins.yml`; `off` takes it out. The build after installs or removes. `run plugin on|off
  [project/]<name>` is the same list, for any plugin in any project. `src/utils/flows.sh` reads
  flows with awk (e2e and host-portability run on the host), so a flow's first keys stay flat
  scalars and block lists, which validate conventions holds it to.
- **A plugin turns on its own automations**: validate conventions fails one whose cron or
  migration runs a machine it does not need.
- **`plugin_sync`** installs each wanted plugin that is new or whose file changed since
  (`applied/plugins/`), then queues each one's migrations that are neither there nor run (after
  every machine, so a daemon never sees one first), removes each one no longer wanted (a
  migration of it that never ran goes too), keeps a hand-edited copy in
  `.decree/archive/` before replacing it, and never touches a machine that is not a repo
  plugin. It runs in adhoc (yq, decree) from each project's `exist.initial.sh`, from
  `_host_plugins` in `existential.sh`, and before `flow on` copies a flow's messages, so a
  daemon never sees a migration before its machine. `./existential.sh run plugin` is the CLI
  (`list`, `on`, `off`, `sync`, `export`).
- **`plugin_export`** is the inverse, and a committed plugin is what export writes for it:
  change it live, `run plugin export <name>`, commit, and every install that has it on gets it
  on its next pull. `needs:` is computed from `invoke.machine`, `emits:`, `decree emit
  --machine X` (scripts and lib), and every installed plugin whose lib path its code names
  (`${DECREE_LIB}/model.sh`, `lib/rss`, `../you-were-here/digest`).
- **`lib/` is installed, not shipped.** `automation/lib/` holds only the plugin system's own
  (`automations/`) and the daemon's (`file-handlers.ts`, `attention-notify.sh`,
  `skill-notes.md`), copied into each project every run (`src/lib/plugin.sh`, which removes a
  file the repo dropped: `.decree/lib/.shared`). Everything else in a project's `.decree/lib/` is
  some plugin's `lib:`, at `${DECREE_LIB}/<path>`; a path another plugin has is refused.
  code-server reads `model.sh`, `pi.sh` and `capture/` from `/workspace/.decree/lib/`.
- **Yours ships as an example.** A lib file meant to be edited (the newsletter's `feeds.txt`
  and `taste.md`, the departments, the agent-handoff processor) is `<name>.exist.<ext>` in the
  plugin, copied to its real name once, never overwritten, removed or exported. So are
  `automation/handlers.exist.yml` and `decree-go-rest.exist.yml`, copied into the workspace
  once. Code that lists a lib folder skips `*.exist.*`.
- **The plugin system is not a plugin**: `plugin`, `plugin_share`, `plugin_offer`,
  `plugin_request` and `notify` (`PLUGIN_KERNEL`) stay in `automation/machines/` and
  `scripts/`, copied over every run, and no plugin by those names installs. `plugin` installs
  one accepted into `notes/automations/` (reconcile files it); the three `plugin_*` ask
  another stack for a plugin, send one, and take one offered into `ai/proposed/`.
- A plugin script's `# shellcheck source=` is `../../lib/…`, because it is installed at
  `scripts/<name>/<script>.sh`. `test lint` and `test typecheck` unpack plugins that way first.
- automation-backup bind-mounts its installed `machines/`, `scripts/` and `lib/`: gitignored,
  but rendered from the tracked repo every run, like a rendered file, not state.

## Rules

- **Names are snake_case.** A machine is `machines/<name>.yml` and its script is
  `scripts/<name>.sh`, the same name. Cron, migration and inbox files keep their
  kebab-case filenames; only `machine:` changes.
- **Start with the simplest machine:** one state that invokes the script, plus
  `done` and `failed`. Add states only when a real run shows the need.
- **Params are declared.** Every key a message passes under `params:` is in the
  machine's `data:` with a default, and the script reads `DECREE_DATA_<NAME>`.
  decree fails a run whose params are undeclared, so a producer (cron file,
  webhook endpoint, `decree emit`) can only send names the machine knows.
- **Chaining is `decree emit --machine X --param k=v`**, and the emitting state
  lists `emits: [X]` so `decree check` and `decree graph` see the chain.
- **Scripts are executable** (`755`). decree runs them by path and `decree check`
  refuses a script without `+x` (V12), the exception to the repo's `644` default.
- **Config, not secrets, goes in `automation/.env`** (gitignored, mounted over
  `workspace/.decree/.env` so it never syncs; `.env.example` is the template). Secrets come from compose `environment:`, which wins over it. Shared code is library plugins' lib, installed
  at `$DECREE_LIB`; state a machine keeps between runs is in `$DECREE_STORE`,
  declared under the machine's `store:`.
- **A migration waits for its own service** in a first `wait_for_<service>` state.
  There is no gate: the entrypoint is `exec decree daemon`, which runs migrations
  in order, and a failed one blocks the rest until `decree process --retry`.
- **Two ways for a machine to reach AI:** `lib/model.sh` (`model_chat`,
  `model_gate`), one answer from the role's OpenAI-compatible `/v1` URL; and
  `lib/agent.sh` (`agent`, `agent_ready`), Claude Code with tools through
  `lib/ai.sh`. That file is decree's `ai` helper exactly as `decree init`
  writes it, and `test decree` fails when they differ, so update it by copying, never by
  editing. `automation`'s image ships `claude` (pinned, updater and telemetry off). It is
  signed in once with `docker exec -it automation claude` and `/login`, which lives in
  `/data`, or with `AUTOMATION_ANTHROPIC_API_KEY` / `AUTOMATION_CLAUDE_CODE_OAUTH_TOKEN`.
  Headless calls use `AUTOMATION_CLAUDE_PERMISSION_MODE`, default `auto`; notes, which
  Claude may not change, are mounted read-only. The workspace's `develop` writes a
  machine with Claude when `agent_ready`, else with the chat model, and tells it about
  `agent` only then. `lib/pi.sh` is the third way: `pi_run` runs pi (baked
  into the decree image, pinned) on the chat role with a department's tools
  (`lib/departments/`); `pi_configure` writes its provider and MCP servers
  on every boot of the `automation` daemon and of code-server.

## Around the daemons

- **Webhook:** `automation-webhook` (its own folder and flag, an add-on outside Core;
  everything it triggers also runs from code-server's terminal) runs decree-go-rest with its daemon off, over
  the `automation` project (read-only, `inbox/` writable). Endpoints are
  `workspace/.decree/decree-go-rest.yml` (seeded from `automation/`); edits load
  without a restart.
- **Whoever can write `workspace/` can write automations.** That is the point
  (the user directs agents to), and it means every agent with the workspace
  mounted can add a script the `automation` daemon runs with
  its credentials. Keep secrets out of `workspace/` for the same reason.
- **File handlers:** `automation/lib/file-handlers.ts`, kept running by the `automation`
  entrypoint, watches all of `/workspace` and emits `--param path= --param change=` for every
  entry in `workspace/.decree/handlers.yml` whose glob matches, after the file is `quiet`
  seconds unchanged (30 by default; a delete fires at once). `.git/` and anything `git
  check-ignore` ignores never fires, the same rule as `workspace_sync`; nothing else is
  filtered. A handler's machine must declare `path` and `change`, or `decree emit` refuses it
  and the watcher logs that. The decree skill learns this from `automation/lib/skill-notes.md`.
  Nextcloud's `/files` webhook is the optional older path. Tested by
  `src/test/unit/test-file-handlers.sh`.
- **Telemetry is the event log.** alloy ships `runs/*/events.jsonl` and script
  logs to Loki and derives `decree_runs_total{daemon, machine, state}` and
  `decree_run_duration_milliseconds` for Prometheus. A failed `automation-backup` run
  alerts through Grafana (`hosting/grafana/provisioning/alerting/decree.yaml`) to ntfy.
  There are no hooks. `clean_runs` prunes runs older than 7 days.
- **A run that needs you pages you:** `automation/lib/attention-notify.sh`, looped by the
  `automation` entrypoint (`ATTENTION_NOTIFY=1`), turns each new file in
  `workspace/.decree/attention/` (failed, interrupted, waiting on a person, a hold) into one
  `notify` run, keyed per run, status and state in `/data/attention-notified`. It is not a
  decree run and never reports a `notify` run, so a broken ntfy cannot loop. Grafana's alert
  covers only `automation-backup`, so nothing is sent twice. A wait whose `person` state has a
  `timeout` is not sent: it ends without you (a `gpu_lease` in line). Tested by
  `src/test/unit/test-attention-notify.sh`.
- **Activating a cron** is copying its template into that project's `cron/`.
  Cron files are re-read every tick, so no restart. The default flows are copied by
  `services/automation/exist.initial.sh` whenever the active copy is missing. `automation-backup`
  is off by default; when on, its `exist.initial.sh` does the same for `triage`, `clean-runs` and
  `workspace-sync`.
- **Gate:** `./existential.sh test decree` assembles each project (the plugin system and
  every plugin; automation-backup's set) with every shipped template queued and runs
  `decree check`, then checks each plugin alone with only what its `needs:` reach.
