# decree in existential

decree itself (messages, machines, scripts, plugins, `decree check`, `emit`, `install`,
`status`) is the `/decree` skill (`.claude/skills/decree/`, the files `decree init` writes;
copy them from a fresh `decree init` on a version bump, never hand-edit them). This file is
only what existential adds on top. Every daemon runs decree **0.6.0**, pinned in
`services/automation/decree/Dockerfile` (`DECREE_TAG`), which CI and a host's install steps
read too, and the webhook image is decree-go-rest 0.6.0, which bundles it.

## One place, three projects

**Every machine, script, lib file, cron file and order file the repo ships is in
`automation/plugins/`**, and nowhere else. Each is a decree plugin file. A plugin's
`x-exist-project` says which decree project runs it (one name or a block list); what is on is
one list, `automation/plugins.yml`. A project's `.decree/plugins/` is written from these by the
sync, and `decree install` installs them into `.decree/machines/<name>/`. Neither is committed,
the repo's own `.decree` included (but for its order files and their record, below).

| `x-exist-project` | `automation` | `backup` | `host` |
|---|---|---|---|
| project (`.decree`) | `workspace/.decree` (`volumes/workspace_data/.decree`) | `services/automation-backup/`, mounted as `/work/.decree` | the repo's own `.decree`, run by a decree daemon on the host |
| runs | everything that reasons, routes, or calls a service API | backups, `triage`, `notes_pull`, `workspace_sync`: bulk mounts and master credentials, no AI | `update`, `reporting`, `boot`, `check_versions`, `ubuntu_upgrade`, and the machines that develop this repo (`repo_develop`, `repo_qa`) |
| always has | the plugin system: `notify`, `skill` | `notify` | nothing |
| crons | each plugin's own (`cron:`), installed with it; yours are a plugin of cron files, accepted | the same: `service-triage`, `workspace-sync`, `notes-pull` and one `backup-<service>` flow per service | each plugin's own |
| order files | each plugin's own (`order:`), run by decree's `decree_order` plugin | none | **the repo's**, tracked in `.decree/machines/repo_develop/order/` with `state/order.git.txt`; a host plugin carries none (validate conventions) |

Each project has its own `inbox/`, `runs/` and `store/`. The seeded `.gitignore` keeps
`workspace/.decree`'s run state (runs, store, inbox, attention, logs) from syncing; everything
else there syncs, and `decree install` draws each machine's `graph.md`. A machine more than one
project runs (`notify`) is one file, tagged for each.

**The tag is the wall.** `automation` hands what it reads to a model, so what it can read
or write is what a prompt injection can. Three things keep it from `backup` and the host:

- **`/repo` is mounted only into `automation-backup`**, read-only. `automation` mounts the
  workspace, `automation/.env` and `/secrets`, and nothing else of the repo: not
  `automation/plugins/`, not `automation/plugins.yml`.
- **A project gets only what is tagged for it** (`plugin_wanted`), and what a plugin
  `needs:` must carry each of its own tags (validate conventions), so turning something on
  never pulls an automation-only plugin into another project.
- **`run plugin export` reads from the most privileged project that runs the plugin** (host,
  then backup, then automation: `source_of`). An edit in the workspace can only ever be
  exported into a plugin that only `automation` runs.

## Plugins

**A plugin is a file**: `automation/plugins/<name>.md`, decree's plugin file (`name`, `extends`,
`needs`, `machine`, `scripts`, `cron`, `state`, `order`) with existential's keys beside them, each
`x-exist-<key>`, which decree ignores and `decree export` keeps (`project`, `lib`, `handlers`,
`when`, `endpoints`; `automation/lib/plugin.sh` says what each is). Validate
conventions fails any other key. With no `machine` (and no `extends`) it is a **flow**, in
`automation/plugins/flows/<name>.md`: one curated thing the stack does (`x-exist-title`,
`-tagline`, `-docs`, `-services`, `-e2e`, `needs`, then `cron`, `order`, `x-exist-examples`
and a body of what is left for a person), or, without a tagline, lib others need (`model`,
`agent`, `pi` with `departments/`, `firecrawl`, `rss`, `repo`, the file processors `ocr`,
`transcribe`, `agent_handoff`). decree installs a flow as a library plugin named
`flow_<name>` (snake_case: decree's names are), so its cron and order files have a folder.
One name space across both folders (validate conventions). A `decree_*` name in `needs:` or
`extends:` is one of decree's official plugins, which the sync adds with `decree install <name>`.

- **What is on is one file**: `automation/plugins.yml` (`on:`, `auto_update`; gitignored),
  written the first time from `automation/plugins.exist.yml`, which is what every install
  starts with: `note-to-automation`, `clean-runs` and `health-checks`, and nothing else.
  **Opt-in is the rule**: every other flow, in every project, is off until a person turns it
  on. `clean-runs` (decree's `decree_prune`) is tagged for all three projects; on the host it asks for
  no daemon (`_host_plugins` does not count it). An install from when each project had its
  own list has them folded in once (`plugins_seed` in `src/utils/flows.sh`, awk: a worker with
  no engine runs it), and one from before any list keeps what it had (`plugin.sh seed`).
  A project has exactly what `on:` lists for it plus everything that `needs:`.
- **`./existential.sh flow`** is the picker over flows with a tagline (`src/flows.sh`): `on`
  asks, per service, to turn on each that its flows need and is off (`x-exist-services`,
  unless the GPU answer forbids one; no answer is no) and adds it to `plugins.yml`; `off`
  takes it out. The build after installs or removes. `run plugin on|off <name>` is the same
  list, for any plugin, and syncs the projects it is tagged for at once. `src/utils/flows.sh`
  reads flows with awk (e2e and host-portability run on the host), so a flow's keys stay flat
  scalars and block lists, which validate conventions holds it to.
- **A plugin turns on its own automations**: validate conventions fails one whose cron or
  order file runs a machine it does not need.
- **`plugin_sync`** writes the project's `.decree/plugins/`: each wanted plugin's file (as
  decree names it, a changed one only named while `auto_update` is false), each official one it
  needs, and removes each it wrote before (`.decree/plugins/.existential`) and no longer wants.
  Then `decree install` installs all of it: a changed plugin again, an installed copy edited in
  place archived first in `.decree/archive/<name>/`, a removed plugin's copy gone (its
  `state/` and `order/` stay). Cron files are installed with a plugin once and are then the
  project's (decree's rule). After that, what decree does not install (`plugin_extras`): each
  plugin's `x-exist-lib`, handlers and endpoints, the ones it added last time taken out first.
  Then the order files: a migration decree 0.5 ran is recorded as run, and one that has not
  run queues one `decree_order` run. It never touches a machine folder no plugin names. It runs in
  adhoc (yq, decree) from each project's `exist.initial.sh` and from `_host_plugins` in
  `existential.sh`; on a worker with no engine, on the host. `./existential.sh run plugin` is
  the CLI (`list`, `on`, `off`, `sync`, `export`, `offers`, `accept`).
- **decree 0.5's layout is converted once** (`plugin_convert_05`): a copy a plugin installed
  goes (the plugin installs it again), a machine of yours moves to `machines/<name>/`, and the
  registry, applied copies, migrations and flat scripts are kept in `.decree/archive/0.5/`.
- **`run plugin export <name>`** is `decree export` in the source project, with `needs:` put
  back in the repo's names and `note_watch`'s emits as the repo has them: change it live,
  export, commit, and every install that has it on gets it on its next pull.
- **`lib/` is ours, not decree's.** decree 0.6 has no `.decree/lib/` and no `$DECREE_LIB`; it
  lets a project keep a folder of its own, and this one does. `automation/lib/` holds only the
  plugin system's own (`automations/`) and the daemon's (`file-handlers.ts`,
  `attention-notify.sh`, `skill-notes.md`), copied into each project every run
  (`.decree/lib/.shared`). Everything else there is some plugin's `x-exist-lib`
  (`.decree/lib/.plugins`); the gate fails two plugins shipping one path. A script reaches it
  as `.decree/lib/<path>` (a script runs in the project root); a lib file reaches another
  beside it by its own path. code-server reads `model.sh`, `pi.sh` and `capture/` from
  `/workspace/.decree/lib/`.
- **Yours is in the store.** Data a person edits (the newsletter's `feeds.txt` and `taste.md`,
  pi's departments) is a plugin's `state:`, written once, never overwritten, removed or
  exported. In `automation` and `backup` each machine's `state/` is a link to
  `.decree/store/<name>/` (`plugin_state_links`), since `machines/` is read-only there and the
  store is not: the store is where a person and every container write it. On the host,
  `state/` is a folder. Code a person tunes (the agent-handoff processor's CRITERIA) is still
  code: changed in its plugin file. The project's own config ships as examples copied once:
  `automation/handlers.exist.yml` and `decree-go-rest.exist.yml`.
- **Triggers are plugin keys.** `cron:` (a cron file, `machines/<name>/cron/`),
  `x-exist-handlers` (entries in `.decree/handlers.yml` for its machine) and `x-exist-when`
  (the kind of note that starts it: `note_watch` reads it from `.decree/plugins/`, and the
  sync adds the machine to `note_watch`'s `emits`). There is no `.decree/cron/`: a schedule
  of yours is a plugin with only `cron:` (`plugin_is` takes one as a plugin, not a spec),
  such as the `gmail_transactions` that `exist.gmail-transactions-cron.sh` offers. A sync
  installs a plugin's cron files once, so an edited copy is kept; `accept` passes `--cron`,
  so what a person approved is what runs. The sync names any file left in `.decree/cron/`.
- **The plugin system is `notify`, and in `automation` `skill`** (`PLUGIN_KERNEL`): files in
  `automation/plugins/` like the rest, but in every project they are tagged for whatever is on,
  and never replaced by an accepted plugin. `skill` extends `decree_skill` to write the decree
  skill to `/workspace/.claude/skills/decree` (not `/work`, the project root) at each daemon
  start; the entrypoint writes this project's `existential` skill beside it. Trading plugins with another stack
  (`plugin_share`, `plugin_offer`, `plugin_request`, with their webhook endpoints) is the
  `plugin-sharing` flow, off until asked for; `plugin_share` sends the plugin file a machine
  was installed from. There is no machine that installs a plugin.
- **decree's official plugins are `decree_*`, used as they are or extended, never forked.**
  decree installs each from the binary, and `check` fails an edited one: a change to one is a
  plugin here that `extends:` it under its own name and holds only the files it changes,
  installed over the base (which is installed too, idle). The sync installs only its own
  plugins, by name, so decree adds each official one they need and removes it when nothing
  needs it any more (decree A15); `decree_order` must never outlive the `repo` flow on a
  host, or it would run the repo's order files at boot.
  Used: `decree_order` (order files), `decree_ai` (`agent.sh`'s `ai`), `decree_prune`
  (`clean-runs`); extended: `decree_lease` (`gpu_lease`: its `resources` and
  `swap/gpu.sh` are scripts, so they install read-only; its `callback.sh` takes the
  holder's address from `automation/.env`, never from the request, and `gpu_release` is how
  a POST answers a lease, refusing any run that is not `gpu_lease`'s; and, on a GPU box's host,
  `ai_box_gpu`: modes `llm`, `comfy`, `tts`, its swap unloading llama.cpp's router, ComfyUI and
  `ai_box_tts`'s tmux session; a separate host-only plugin, so a host that also runs the stack
  never has two queues for one card; its lease is served over decree-go-rest's emit, read and
  reply endpoints, no release machine), `decree_skill`
  (`skill`), `decree_develop` and `decree_qa` (`repo_develop`, `repo_qa`). Not
  `decree_registry` (the model endpoint resolvers do that) nor `decree_newsletter` (its
  feeds are scripts in decree 0.6, and here they are data a person edits in the store).
- **Offer and accept** is the one way code made in the workspace gets in, and the critical
  journey to keep whole (`site/docs/plugins/offer-and-accept.md`):
  1. `plugins/`, `machines/` and `lib/` of `workspace/.decree` are mounted **read-only** in
     every container that mounts the workspace (`automation`, by both its paths; code-server;
     Nextcloud and its cron; `automation-backup`), and `workspace_sync` filters them out both
     ways. validate conventions fails a compose template that mounts the workspace writable
     without them. decree itself never installs (only `decree install` does, which only the
     host runs), and a daemon over a read-only `machines/` runs what is installed.
  2. So everything in a container can only **offer**: one plugin file in
     `workspace/ai/proposed/<name>.md`. `develop` builds one from an accepted spec
     (`notes/automations/<name>.md`, handed over by `reconcile`), installs it into a scratch
     copy of the project to pass `decree check` (`plugin_try`), and writes the offer;
     `plugin_offer` writes one another stack sent; an agent in code-server writes one by hand
     (`automation/lib/skill-notes.md`, the workspace's `existential` skill, teaches it). Each
     tells the person through `plugin_offered` (`lib/plugin.sh`): where to read
     it, and the command.
  3. `./existential.sh run plugin accept <name>` (`src/lib/plugin.sh`), on the host, is the
     only installer: it prints what the plugin starts on, needs and runs, requires a terminal
     and a typed yes, refuses a name the repo or decree ships, an endpoint that emits to
     another machine and a need the automation project does not run, copies the file to
     `automation/plugins/local/` (gitignored) with `x-exist-project: automation` forced, turns
     it on and syncs; a failed install is taken back out. `plugin_wanted` never gives a
     `local/` plugin to another project.
- **The repo's own `.decree` is the host project.** Its `repo_develop` (`decree_develop`
  with the gate `.githooks/pre-push`, `conventions.md` from CLAUDE.md's rules and the
  declarative order files, and the `requirements` its precheck checks) and `repo_qa`
  (`decree_qa`, handing bugs to `repo_develop` by a needs map) are host plugins like
  `update`, off until `run plugin on repo_develop` (and `repo_qa`); both need the `repo`
  flow, which needs `decree_order`. The repo's migrations are order files,
  `.decree/machines/repo_develop/order/`, and declarative: `decree_order` runs each once and
  again when it is edited, and `decree_develop`'s `commit` records it in
  `state/order.git.txt` with the work. Tracked there: only those two and `.gitignore`. To
  change one of these machines, edit its plugin file or edit the installed copy and `run
  plugin export`, which writes only what differs from the base.
- automation-backup bind-mounts its installed `plugins/`, `machines/` and `lib/`: gitignored,
  but written from the tracked repo every run, like a rendered file, not state.

## Rules

- **Names are snake_case.** A machine is `machines/<name>/machine.yml` and its scripts are in
  `machines/<name>/scripts/`. Cron, order and inbox files keep their kebab-case filenames; only
  `machine:` changes.
- **Start with the simplest machine:** one state that invokes the script, plus
  `done` and `failed`. Add states only when a real run shows the need.
- **Params are declared.** Every key a message passes under `params:` is in the
  machine's `data:` with a default, and the script reads `DECREE_DATA_<NAME>`.
  decree fails a run whose params are undeclared, so a producer (cron file,
  webhook endpoint, `decree emit`) can only send names the machine knows.
- **Chaining is `decree emit --machine X --param k=v`**, and the emitting state
  lists `emits: [X]` so `decree check` and `decree graph` see the chain.
- **A script starts `#!`**: decree installs a plugin's script executable only then.
- **Config, not secrets, goes in `automation/.env`** (gitignored, mounted over
  `workspace/.decree/.env` so it never syncs; `.env.example` is the template). Secrets come
  from compose `environment:`, which wins over it. Shared code is library plugins'
  `x-exist-lib`, at `.decree/lib/`; state a machine keeps between runs is in
  `$DECREE_STATE_DIR`, declared under the machine's `state_files:`.
- **A wait no person answers is `attention: false`** (`decree_lease`'s line and hold), so it
  never reaches `.decree/attention/`.
- **An order file waits for its own service** in a first `wait_for_<service>` state.
  There is no gate: the entrypoint is `exec decree daemon`, whose `decree_order` plugin runs order
  files at start, in order, and a failed one stops the rest until `decree retry <id>`.
- **Two ways for a machine to reach AI:** `lib/model.sh` (`model_chat`,
  `model_gate`), one answer from the role's OpenAI-compatible `/v1` URL; and
  `lib/agent.sh` (`agent`, `agent_ready`), Claude Code with tools through `ai`, from decree's
  official `decree_ai` plugin (`.decree/machines/decree_ai/scripts/ai.sh`), which the `agent` flow needs.
  `automation`'s image ships `claude` (pinned, updater and telemetry off). It is
  signed in once with `docker exec -it automation claude` and `/login`, which lives in
  `/data`, or with `AUTOMATION_ANTHROPIC_API_KEY` / `AUTOMATION_CLAUDE_CODE_OAUTH_TOKEN`.
  Headless calls use `AUTOMATION_CLAUDE_PERMISSION_MODE`, default `auto`; notes, which
  Claude may not change, are mounted read-only. The workspace's `develop` writes a
  machine with Claude when `agent_ready`, else with the chat model, and tells it about
  `agent` only then. `lib/pi.sh` is the third way: `pi_run` runs pi (baked
  into the decree image, pinned) on the chat role with a department's tools
  (`store/agent_task/departments/`); `pi_configure` writes its provider and MCP servers
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
  and the watcher logs that. Claude learns this from `automation/lib/skill-notes.md`.
  Nextcloud's `/files` webhook is the optional older path. Tested by
  `src/test/unit/test-file-handlers.sh`.
- **Telemetry is the event log.** Each host's alloy, which the `reporting` plugin keeps
  running, ships `runs/*/events.jsonl` and script logs of all three projects to Loki, live,
  labelled `host` and `project`; Grafana counts runs from those lines. A failed run in
  `automation-backup` or `host`, or a backup with no `done` run in 48h, alerts through Grafana (`hosting/grafana/provisioning/alerting/decree.yaml`) to ntfy.
  There are no hooks. decree's `decree_prune` (the `clean-runs` flow) deletes runs older than 30 days.
- **A run that needs you pages you:** `automation/lib/attention-notify.sh`, looped by the
  `automation` entrypoint (`ATTENTION_NOTIFY=1`), turns each new file in
  `workspace/.decree/attention/` (failed, interrupted, waiting on a person, a hold) into one
  `notify` run, keyed per run, status and state in `/data/attention-notified`. It is not a
  decree run and never reports a `notify` run, so a broken ntfy cannot loop. Grafana's alert
  covers only `automation-backup`, so nothing is sent twice. A wait whose `reply` state has a
  `timeout` is not sent: it ends without you (`plugin_share` asks you itself). Tested by
  `src/test/unit/test-attention-notify.sh`.
- **A cron is active when it is in a machine's `cron/`**, installed with its plugin (yours
  included). Cron files are re-read every tick, so no restart. `automation-backup`
  is off by default; when on, it schedules only what is on (`clean-runs`, from the defaults).
- **Gate:** `./existential.sh test decree` assembles each project (automation, backup,
  host) from every plugin tagged for it, installed by decree, with every shipped order file
  and example queued, and runs `decree check`, then checks each plugin alone with only what
  its `needs:` reach.

**Offers (peers).** A host plugin that serves the other hosts ships `scripts/offers.sh`, one
JSON object per line (`service`, `url`, and `lease`/`api` or `start`/`stop`), `localhost`
meaning this host. `reporting` pushes them as `kind="offer"`, with `localhost` swapped for
`EXIST_HOST_ADDRESS` (else the tailnet name, else the hostname), and `src/lib/peers.sh`
(`./existential.sh run peers`) reads each host's latest back from the controller's Loki.
The controller only answers the question; traffic goes host to host.
The **fleet** lib (`flows/fleet.md`, `fleet_use`/`fleet_done`) is how the stack leases a GPU
service another host offers: `model_chat`/`pi_run` (`llm`) and `comfy` call it, a keeper per
container holds one lease for a run of calls and releases it `FLEET_IDLE` (5) seconds after the
last (comfy: after ComfyUI's queue empties too), and a new lease asks the controller again, so
a service moved between hosts is followed. Leases are 10 minutes, renewed by the keeper.
`EXIST_FLEET_SECRET` (the same on every host) is every box's decree-go-rest secret; blank, or no
offer, and callers use their own addresses with no lease. `peers.sh` sources the same lib.
