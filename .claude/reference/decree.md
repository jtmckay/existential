# decree in existential

decree itself — messages, machines, scripts, `decree check`, `emit`, `status` — is
the `/decree` skill (`.claude/skills/decree/`, written by `decree skill --ai claude`;
regenerate it on a version bump, never hand-edit it). This file is only what
existential adds on top. Both daemons run decree **0.5.0**, pinned in
`services/automation/decree/Dockerfile`; the webhook image bundles the same version.

## One place, three projects

**Every machine, script, lib file, cron and migration the repo ships is in
`automation/plugins/`**, and nowhere else. A plugin's `project:` says which decree project
runs it (one name or a block list); what is on is one list, `automation/plugins.yml`. The
installed copies (`machines/`, `scripts/`, `lib/`, `cron/` in each project) are gitignored
everywhere, the repo's own `.decree` included.

| `project:` | `automation` | `backup` | `host` |
|---|---|---|---|
| project (`.decree`) | `workspace/.decree` (`volumes/workspace_data/.decree`) | `services/automation-backup/`, mounted as `/work/.decree` | the repo's own `.decree`, run by a decree daemon on the host |
| runs | everything that reasons, routes, or calls a service API | backups, `triage`, `notes_pull`, `workspace_sync`: bulk mounts and master credentials, no AI | `update`, `reporting`, `boot`, `check_versions`, `ubuntu_upgrade`, and the machines that develop this repo (`repo_develop`, `repo_reconcile`, `repo_infra`, `repo_qa`) |
| always has | the plugin system: `plugin`, `notify` | `notify` | nothing |
| crons | each plugin's own (`cron:`), in and out with it | the same: `service-triage`, `workspace-sync`, `notes-pull` and one `backup-<service>` flow per service | each plugin's own |
| migrations | each plugin's own (`migrations:`) | none | **the repo's**, tracked in `.decree/migrations/` with `applied/` and `processed.md`; a host plugin carries none (validate conventions) |

Each project has its own `inbox/`, `runs/`, `store/`, `cron/` and `processed.md`.
The seeded `.gitignore` keeps `workspace/.decree`'s run state (runs, store, inbox,
attention, logs) from syncing; everything else there syncs, and `graph/` is drawn by the
entrypoint whenever a machine changes; nothing in the repo is a graph. A machine more than
one project runs (`notify`, `clean_runs`) is one file, tagged for each.

**The tag is the wall.** `automation` hands what it reads to a model, so what it can read
or write is what a prompt injection can. Three things keep it from `backup` and the host:

- **`/repo` is mounted only into `automation-backup`**, read-only. `automation` mounts the
  workspace, `automation/.env` and `/secrets`, and nothing else of the repo: not
  `automation/plugins/`, not `automation/plugins.yml`.
- **A project installs only what is tagged for it** (`plugin_wanted`), and what a plugin
  `needs:` must carry each of its own tags (validate conventions), so turning something on
  never pulls an automation-only plugin into another project.
- **`run plugin export` reads from the most privileged project that runs the plugin** (host,
  then backup, then automation: `source_of`). An edit in the workspace can only ever be
  exported into a plugin that only `automation` runs.

A plugin accepted from another stack (`notes/automations/`, the `plugin` machine) installs
into the workspace project alone, and cannot take a plugin-system name.

## Plugins

**A plugin is a file**: `automation/plugins/<name>.md`, everything in its frontmatter (`project`,
`chart`, `scripts`, `lib`, `cron`, `migrations`, `endpoints`, `needs`; `automation/lib/automations/plugin.sh`
says what each is). With no `chart` it is a **flow**, in `automation/plugins/flows/<name>.md`:
one curated thing the stack does (`name`, `tagline`, `docs`, `services`, `needs`, `e2e`, then
`cron`, `migrations`, `examples` and a body of what is left for a person), or, without a tagline,
lib others need (`model`, `agent` with decree's `ai.sh`, `pi` with `departments/`, `firecrawl`,
`rss`, `repo`, the file processors `ocr`, `transcribe`, `agent_handoff`). One name space across both
folders (validate conventions). The installed copies are never committed.

- **What is on is one file**: `automation/plugins.yml` (`on:`, `auto_update`; gitignored),
  written the first time from `automation/plugins.exist.yml`, which is what every install
  starts with: `note-to-automation`, `clean-runs` and `health-checks`, and nothing else.
  **Opt-in is the rule**: every other flow, in every project, is off until a person turns it
  on. `clean-runs` is tagged for all three projects; on the host it asks for no daemon
  (`_host_plugins` does not count it). An
  install from when each project had its own list (`workspace/.decree/plugins.yml`,
  `host/.decree/plugins.yml`, `services/automation-backup/plugins.yml`) has them folded in
  once (`plugins_seed` in `src/utils/flows.sh`, awk: a worker with no engine runs it), and one
  from before any list keeps what it had (`plugin.sh seed`).
  A project has exactly what `on:` lists for it plus everything that `needs:`, so a flow
  another flow that is on needs stays on.
- **`./existential.sh flow`** is the picker over flows with a tagline (`src/flows.sh`): `on`
  asks, per service, to turn on each that its flows need and is off (`services:`, unless the GPU
  answer forbids one; no answer is no) and adds
  it to `plugins.yml`; `off` takes it out. The build after installs or removes. `run plugin on|off
  <name>` is the same list, for any plugin, and syncs the projects it is tagged for at once. `src/utils/flows.sh` reads
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
- **Yours is in the store.** Data a person edits (the newsletter's `feeds.txt` and `taste.md`,
  pi's departments) is a plugin's `store:`, written once to `.decree/store/<plugin>/<path>`,
  never overwritten, removed or exported, and writable from every container. What an older
  install kept beside the code in `lib/` moves over on the next install. Code a person tunes
  (the agent-handoff processor's CRITERIA) is still code: changed in its plugin file. The
  project's own config ships as examples copied once: `automation/handlers.exist.yml` and
  `decree-go-rest.exist.yml`.
- **Triggers are plugin keys.** `cron:` (a cron file), `handlers:` (entries in
  `.decree/handlers.yml` for its machine) and `when:` (the kind of note that starts it:
  kept in the registry, and the machine added to `note_watch`'s `emits`).
- **The plugin system is one plugin, `notify`** (`PLUGIN_KERNEL`): a file in
  `automation/plugins/` like the rest, but installed in every project it is tagged for
  whatever is on, and never replaced by an accepted plugin. Trading plugins with another stack
  (`plugin_share`, `plugin_offer`, `plugin_request`, with their webhook endpoints) is the
  `plugin-sharing` flow, off until asked for. There is no machine that installs a plugin.
- **Offer and accept** is the one way code made in the workspace gets in, and the critical
  journey to keep whole (`site/docs/plugins/offer-and-accept.md`):
  1. `machines/`, `scripts/` and `lib/` of `workspace/.decree` are mounted **read-only** in
     every container that mounts the workspace (`automation`, by both its paths; code-server;
     Nextcloud and its cron; `automation-backup`), and `workspace_sync` filters them out both
     ways. validate conventions fails a compose template that mounts the workspace writable
     without them.
  2. So everything in a container can only **offer**: one plugin file in
     `workspace/ai/proposed/<name>.md`. `develop` builds one from an accepted spec
     (`notes/automations/<name>.md`, handed over by `reconcile`), installs it into a scratch
     copy of the project to pass `decree check`, and writes the offer; `plugin_offer` writes one
     another stack sent; an agent in code-server writes one by hand
     (`automation/lib/skill-notes.md` teaches the decree skill this). Each tells the person
     through `plugin_offered` (`lib/automations/plugin.sh`): where to read it, and the command.
  3. `./existential.sh run plugin accept <name>` (`src/lib/plugin.sh`), on the host, is the
     only installer: it prints what the plugin starts on, needs and runs, requires a terminal
     and a typed yes, refuses a name the repo ships and a need the automation project does not
     run, copies the file to `automation/plugins/local/` (gitignored) with `project:
     automation` forced, turns it on and syncs; a failed install is taken back out.
     `plugin_wanted` never gives a `local/` plugin to another project.
  An automation an older install's `develop` built in place (registry `kind: note|file|cron`)
  keeps running and is never rebuilt.
- **The repo's own `.decree` is the host project.** Its `repo_develop` (implement → gate, the
  gate being `.githooks/pre-push`), `repo_reconcile`, `repo_infra` and `repo_qa` are host
  plugins like `update`, off until `run plugin on repo_reconcile` (and `repo_infra`,
  `repo_qa`); the steps they share (`clean_tree`, `commit`, `keep`, `record`) are the `repo`
  flow's lib, and decree's `ai.sh` is `agent`'s, tagged for both. Tracked there: only
  `migrations/`, `applied/`, `processed.md`, `requirements` (what `repo_infra` declares) and
  `.gitignore`. To change one of these machines, edit its plugin file or edit the installed
  copy and `run plugin export`.
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
- **Whoever can write `workspace/` can write messages, not code.** A cron file, an inbox
  message or a handler there starts a machine that is already installed, with the params it
  declares; no agent with the workspace mounted can add or change a script (offer and accept,
  above). Keep secrets out of `workspace/` all the same.
- **File handlers:** `automation/lib/file-handlers.ts`, kept running by the `automation`
  entrypoint, watches all of `/workspace` and emits `--param path= --param change=` for every
  entry in `workspace/.decree/handlers.yml` whose glob matches, after the file is `quiet`
  seconds unchanged (30 by default; a delete fires at once). `.git/` and anything `git
  check-ignore` ignores never fires, the same rule as `workspace_sync`; nothing else is
  filtered. A handler's machine must declare `path` and `change`, or `decree emit` refuses it
  and the watcher logs that. The decree skill learns this from `automation/lib/skill-notes.md`.
  Nextcloud's `/files` webhook is the optional older path. Tested by
  `src/test/unit/test-file-handlers.sh`.
- **Telemetry is the event log.** Each host's alloy, which the `reporting` plugin keeps
  running, ships `runs/*/events.jsonl` and script logs of all three projects to Loki, live,
  labelled `host` and `project`; Grafana counts runs from those lines. A failed run in
  `automation-backup` or `host`, or a backup with no `done` run in 48h, alerts through Grafana (`hosting/grafana/provisioning/alerting/decree.yaml`) to ntfy.
  There are no hooks. `clean_runs` prunes runs older than 30 days.
- **A run that needs you pages you:** `automation/lib/attention-notify.sh`, looped by the
  `automation` entrypoint (`ATTENTION_NOTIFY=1`), turns each new file in
  `workspace/.decree/attention/` (failed, interrupted, waiting on a person, a hold) into one
  `notify` run, keyed per run, status and state in `/data/attention-notified`. It is not a
  decree run and never reports a `notify` run, so a broken ntfy cannot loop. Grafana's alert
  covers only `automation-backup`, so nothing is sent twice. A wait whose `person` state has a
  `timeout` is not sent: it ends without you (a `gpu_lease` in line). Tested by
  `src/test/unit/test-attention-notify.sh`.
- **A cron is active when it is in that project's `cron/`**, written by the sync that
  installs its plugin. Cron files are re-read every tick, so no restart. `automation-backup`
  is off by default; when on, it schedules only what is on (`clean-runs`, from the defaults).
- **Gate:** `./existential.sh test decree` assembles each project (automation, backup,
  host) from every plugin tagged for it, with every shipped template queued, and runs
  `decree check`, then checks each plugin alone with only what its `needs:` reach.
