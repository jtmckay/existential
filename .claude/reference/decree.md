# decree in existential

decree itself (messages, machines, scripts, plugins, `decree check`, `emit`, `install`,
`status`) is the `/decree` skill (`.claude/skills/decree/`, the files `decree init` writes;
copy them from a fresh `decree init` on a version bump, never hand-edit them). This file is
only what existential adds on top. Every daemon runs decree **0.6.1**, pinned in
`services/automation/decree/Dockerfile` (`DECREE_TAG`), which CI and a host's install steps
read too, and the webhook image is decree-go-rest 0.6.0, which bundles decree 0.6.0 (there is no 0.6.1).

## One place, three projects

**Every machine, script, lib file, cron file and order file the repo ships is in
`automation/plugins/`**, and nowhere else. Each is a decree plugin file. A plugin's
`x-exist-project` says which decree project runs it (one name or a block list). None of it is
on: what is on is each project's own list, `.decree/plugins/.on`. A project's
`.decree/plugins/` is written from these by the sync, and `decree install` installs them into `.decree/machines/<name>/`. Neither is committed,
the repo's own `.decree` included (but for its order files and their record, below).

| `x-exist-project` | `automation` | `backup` | `host` |
|---|---|---|---|
| project (`.decree`) | `workspace/.decree` (`volumes/workspace_data/.decree`) | `services/automation-backup/`, mounted as `/work/.decree` | the repo's own `.decree`, run by a decree daemon on the host |
| runs | everything that reasons, routes, or calls a service API | backups, `triage`, `notes_pull`, `workspace_sync`: bulk mounts and master credentials, no AI | `pull_existential`, `report_host`, `boot_daemon`, `check_versions`, `update_ubuntu`, `lease_gpu`, and the machines that develop this repo (`repo_develop`, `repo_qa`) |
| always has | the plugin system: `notify`, `skill`, `decree_prune` | `notify`, `decree_prune` | `decree_prune`, once anything is on |
| crons | each plugin's own (`cron:`), installed with it; yours are a plugin of cron files in `.decree/plugins/` | the same: `triage`'s, `workspace_sync`'s, `notes_pull`'s, and each backup plugin's nightly and weekly, listing every service it knows | each plugin's own |
| order files | each plugin's own (`order:`), run by decree's `decree_order` plugin | none | **the repo's**, tracked in `.decree/machines/repo_develop/order/` with `state/order.git.txt`; a host plugin carries none (validate conventions) |

Each project has its own `inbox/`, `runs/` and `store/`. The seeded `.gitignore` keeps
`workspace/.decree`'s run state (runs, store, inbox, attention, logs) from syncing; everything
else there syncs, and `decree install` draws each machine's `graph.md`. A machine more than one
project runs (`notify`) is one file, tagged for each.

**The tag is the wall.** `automation` hands what it reads to a model, so what it can read
or write is what a prompt injection can. Three things keep it from `backup` and the host:

- **`/repo` is mounted only into `automation-backup`**, read-only. `automation` mounts the
  workspace, `automation/.env` and `/secrets`, and nothing else of the repo: not
  `automation/plugins/`, nor `backup`'s or the host's list of what is on.
- **A project gets only what is tagged for it** (`plugin_wanted`), and what a plugin
  `needs:` must carry each of its own tags (validate conventions), so turning something on
  never pulls an automation-only plugin into another project.
- **`plugin export` reads from the most privileged project that runs the plugin** (host,
  then backup, then automation: `source_of`). An edit in the workspace can only ever be
  exported into a plugin that only `automation` runs.

## Plugins

**A plugin is a file**: `automation/plugins/<name>.md`, decree's plugin file (`name`, `extends`,
`needs`, `machine`, `scripts`, `cron`, `state`, `order`) with existential's keys beside them, each
`x-exist-<key>`, which decree ignores and `decree export` keeps (`project`, `lib`, `handlers`,
`when`, `endpoints`; `automation/lib/plugin.sh` says what each is). Validate
conventions fails any other key. With no `machine` (and no `extends`) it is lib others need
(`model`, `agent`, `pi` with `departments/`, `firecrawl`, `rss`, `fleet`, `repo`, the file
processors `ocr`, `transcribe`, `agent_handoff`). A `decree_*` name in `needs:` or `extends:` is
one of decree's official plugins, which the sync adds with `decree install <name>`. There are no
flow files: a flow is a section of a Guide page in `site/docs/flows/`, the `service on` and
`plugin on` lines for one job, and a plugin a person turns on (a machine nothing needs) must have
its `plugin on` line on some docs page (validate conventions).

- **What is on is each project's own list**, `.decree/plugins/.on` (never committed): the
  plugins a person turned on there. A project with none starts with `PLUGIN_DEFAULTS` tagged for
  it (`plugin_seed`): `note_watch`, `reconcile`, `service_health`, `pi`, `file_advise` and
  `you_were_here`, all `automation`'s. **Opt-in is the rule**: everything else, in every
  project, is off until a person turns it on. `decree_prune` is in the kernel, so every project
  prunes its runs; **the host's project is not Core**, and `_host_plugins` syncs it only while
  its list names something (`plugin off` syncs it at once, so the last one off is removed). A
  project has exactly what its list names, the kernel, and everything those `needs:`. An
  install from before kept one `automation/plugins.yml` and each sync's `.existential`:
  `_plugins_on` (`src/utils/migrate.sh`) makes each `.on` from the latter, moving a flow's
  installed cron files to the machine each names, and archives the former.
- **`./existential.sh plugin on|off <name>...`** (`src/plugins.sh`) edits the list of each
  project the plugin is tagged for (backup only while automation-backup is on) and syncs each
  at once. `plugin` (exit 3) lists every plugin: `on`, `+` for one something on needs, or off.
  The services a flow uses are `./existential.sh service on`, a separate step.
- **A plugin turns on its own automations**: validate conventions fails one whose cron or
  order file runs a machine it does not need.
- **`plugin_sync`** writes the project's `.decree/plugins/`: each wanted plugin's file, as the
  checkout has it, and removes each whose name is a repo plugin's and that nothing wants.
  Then `decree install` installs all of it: a changed plugin again, an installed copy edited in
  place archived first in `.decree/archive/<name>/`, a removed plugin's copy gone (its
  `state/` and `order/` stay). Cron files are installed with a plugin once and are then the
  project's (decree's rule). After that, what decree does not install (`plugin_extras`): each
  plugin's `x-exist-lib`, handlers and endpoints, the ones it added last time taken out first.
  Then the order files: a migration decree 0.5 ran is recorded as run, and one that has not
  run queues one `decree_order` run. It never touches a machine folder no plugin names. It runs in
  adhoc (yq, decree) from each project's `exist.initial.sh` and from `_host_plugins` in
  `existential.sh`; on a worker with no engine, on the host. `./existential.sh plugin` is
  the CLI (`list`, `on`, `off`, `sync`, `export`).
- **decree 0.5's layout is converted once** (`plugin_convert_05`): a copy a plugin installed
  goes (the plugin installs it again), a machine of yours moves to `machines/<name>/`, and the
  registry, applied copies, migrations and flat scripts are kept in `.decree/archive/0.5/`.
- **`plugin export <name>`** is `decree export` in the source project, with `note_watch`'s
  emits as the repo has them: change it live,
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
  `.decree/store/<name>/` (`plugin_state_links`), so a machine's data lives apart from its
  code: the store is where a person and every container write it. On the host,
  `state/` is a folder. Code a person tunes (the agent-handoff processor's CRITERIA) is still
  code: changed in its plugin file. The project's own config ships as examples copied once:
  `automation/handlers.exist.yml` and `decree-go-rest.exist.yml`.
- **Triggers are plugin keys.** `cron:` (a cron file, `machines/<name>/cron/`),
  `x-exist-handlers` (entries in `.decree/handlers.yml` for its machine) and `x-exist-when`
  (the kind of note that starts it: `note_watch` reads it from `.decree/plugins/`, and the
  sync adds the machine to `note_watch`'s `emits`). There is no `.decree/cron/`: a schedule
  of yours is a plugin with only `cron:` (`plugin_is` takes one as a plugin, not a spec),
  such as the `gmail_transactions` that `exist.gmail-transactions-cron.sh` offers. A sync
  installs a plugin's cron files once, so an edited copy is kept; `decree install --cron <name>`
  installs them again. The sync names any file left in `.decree/cron/`.
- **The plugin system is `notify`, decree's `decree_prune`, and in `automation` `skill`** (`PLUGIN_KERNEL`): files in
  `automation/plugins/` like the rest, but in every project they are tagged for whatever is on,
  and rewritten by every sync. `skill` extends `decree_skill` to write the decree
  skill to `/workspace/.claude/skills/decree` (not `/work`, the project root) at each daemon
  start; the entrypoint writes this project's `existential` skill beside it. Trading plugins with another stack
  (`plugin_share`, `plugin_offer`, `plugin_request`, with their webhook endpoints) is off until
  asked for; `plugin_share` sends the plugin file a machine
  was installed from. There is no machine that installs a plugin.
- **decree's official plugins are `decree_*`, used as they are or extended, never forked.**
  decree installs each from the binary, and `check` fails an edited one: a change to one is a
  plugin here that `extends:` it under its own name and holds only the files it changes,
  installed over the base (which is installed too, idle). The sync installs only its own
  plugins, by name, so decree adds each official one they need and removes it when nothing
  needs it any more (decree A15); `decree_order` must never outlive the `repo` plugin on a
  host, or it would run the repo's order files at boot.
  Used: `decree_order` (order files), `decree_ai` (`agent.sh`'s `ai`), `decree_prune`
  (the kernel's); extended: `decree_lease` (`gpu_lease`: its `resources` and
  `swap/gpu.sh` are scripts, so they install read-only; its `callback.sh` takes the
  holder's address from `automation/.env`, never from the request, and `gpu_release` is how
  a POST answers a lease, refusing any run that is not `gpu_lease`'s; and, on a GPU box's host,
  `lease_gpu`: modes `llm`, `comfy`, `tts`, `strata`, its swap unloading llama.cpp's router and
  ComfyUI, and stopping or starting the TTS tmux session and Strata's container; a separate host-only plugin, so a host that also runs the stack
  never has two queues for one card; its lease is served over decree-go-rest's emit, read and
  reply endpoints, no release machine; that decree-go-rest is the box's `hosting/fleet-api`
  service, pulled as an image and run by Compose, never started from the host), `decree_skill`
  (`skill`), `decree_develop` and `decree_qa` (`repo_develop`, `repo_qa`). Not
  `decree_registry` (the model endpoint resolvers do that) nor `decree_newsletter` (its
  feeds are scripts in decree 0.6, and here they are data a person edits in the store).
- **Your own plugins** (`site/docs/plugins/offer-and-accept.md`): `workspace/.decree` is
  writable in every container that mounts it, so a plugin file in `.decree/plugins/` and `decree
  install <name>` there is a machine. `plugin_sync` removes only a file whose name is a
  repo plugin's, so a file of yours survives every `./existential.sh`, and the repo plugins it
  `needs:` are installed with it; the sync gives it what decree does not install (its `x-exist-handlers`, `-when`, `-lib`,
  `-endpoints`), and `.decree/plugins/.yours` lists them so a deleted one's handlers go.
  `workspace_sync` still filters `plugins/`, `machines/` and `lib/` out both ways. What the stack
  builds on its own is an **offer** in `workspace/ai/proposed/<name>.md`: `develop` builds one
  from an accepted spec (`notes/automations/<name>.md`, handed over by `reconcile`), installs it
  into a scratch copy of the project to pass `decree check` (`plugin_try`), and writes it;
  `plugin_offer` writes one another stack sent. Each tells the person through `plugin_offered`
  (`lib/plugin.sh`) where to read it and the `mv` + `decree install` that installs it. No
  machine installs. backup and the host install only the repo's plugins.
- **The repo's own `.decree` is the host project.** Its `repo_develop` (`decree_develop`
  with the gate `.githooks/pre-push`, `conventions.md` from CLAUDE.md's rules and the
  declarative order files, and the `requirements` its precheck checks) and `repo_qa`
  (`decree_qa`, handing bugs to `repo_develop` by a needs map) are host plugins like
  `pull_existential`, off until `plugin on repo_develop` (and `repo_qa`); both need the `repo`
  plugin, which needs `decree_order`. The repo's desired state is order files,
  `.decree/machines/repo_develop/order/`: the infrastructure numbered first (`00-`…`04-`), then
  one file per feature, named for it, run in byte order of filename. They are declarative:
  `decree_order` runs each once and again when it is edited, and `decree_develop`'s `commit` records it in
  `state/order.git.txt` with the work. Tracked there: only those two and `.gitignore`. To
  change one of these machines, edit its plugin file or edit the installed copy and
  `plugin export`, which writes only what differs from the base.
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
  official `decree_ai` plugin (`.decree/machines/decree_ai/scripts/ai.sh`), which the `agent` plugin needs.
  `automation`'s image ships `claude` (pinned, updater and telemetry off). It shares
  code-server's login (`code_server_data/home/.claude`, mounted as its `CLAUDE_CONFIG_DIR`):
  `/login` once in code-server's terminal signs in both, or `AUTOMATION_ANTHROPIC_API_KEY` / `AUTOMATION_CLAUDE_CODE_OAUTH_TOKEN`.
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
  declares; an agent in code-server can add a plugin of its own (your own plugins,
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
- **Telemetry is the event log.** Each host's alloy, which the `report_host` plugin keeps
  running, ships `runs/*/events.jsonl` and script logs of all three projects to Loki, live,
  labelled `host` and `project`; Grafana counts runs from those lines. A failed run in
  `automation-backup` or `host`, or a backup with no `done` run in 48h, alerts through Grafana (`hosting/grafana/provisioning/alerting/decree.yaml`) to ntfy.
  There are no hooks. decree's `decree_prune` (in every project's kernel) deletes runs older than 30 days.
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
meaning this host. `report_host` pushes them as `kind="offer"`, with `localhost` swapped for
`EXIST_TAILNET_NAME` (else `EXIST_LOCAL_HOST_IP`, else the hostname), and `src/lib/peers.sh`
(`./existential.sh run peers`) reads each host's latest back from the controller's Loki.
The controller's model gateway serves the fleet lib as a plain decree plugin
(`GET /plugins/fleet_gpu.md` on `:4400`, built from the workspace's `.decree/lib/fleet.sh` it
mounts read-only; nothing of the host's `.decree` is read), so a decree project of your own
installs it with `curl ... | decree install -`.
The controller only answers the question; traffic goes host to host.
The **fleet** lib (`plugins/fleet.md`, `fleet_use`/`fleet_done`) is how the stack leases a GPU
service another host offers: `model_chat`/`pi_run` (`llm`) and `comfy` call it, a keeper per
container holds one lease for a run of calls and releases it `FLEET_IDLE` (5) seconds after the
last (comfy: after ComfyUI's queue empties too), and a new lease asks the controller again, so
a service moved between hosts is followed. Leases are 10 minutes, renewed by the keeper.
With `comfy` on in a GPU box's host project (`comfy` and `fleet` are tagged `automation` and
`host`), its offer gains `generate` and `workflows`, the box's `fleet-api` takes
`POST /comfy/<type>/<name>`, and a run writes `state/status/runs/<id>.json`, read by `GET /comfy/run/<id>`.
`EXIST_FLEET_SECRET` (the same on every host) is every GPU box's `fleet-api` secret and the model
gateway's key; blank, or no
offer, and callers use their own addresses with no lease. `peers.sh` sources the same lib.
