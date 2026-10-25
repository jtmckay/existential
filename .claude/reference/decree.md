# decree in existential

decree itself — messages, machines, scripts, `decree check`, `emit`, `status` — is
the `/decree` skill (`.claude/skills/decree/`, written by `decree skill --ai claude`;
regenerate it on a version bump, never hand-edit it). This file is only what
existential adds on top. Both daemons run decree **0.5.0-beta.13**, pinned in
`services/automation/decree/Dockerfile`; the webhook image bundles the same version.

## Two projects

| | `automation` | `automation-backup` |
|---|---|---|
| project (`/work/.decree`) | `workspace/.decree` (`volumes/workspace_data/.decree`) | `services/automation/backup/` |
| machines | seeded once per file from `automation/machines/` | `services/automation/backup/machines/` |
| scripts, lib | scripts seeded from `automation/scripts/`; `automation/lib/` read-only | `automation/scripts/`, `automation/lib/`, read-only |
| cron templates | `flows/<name>/cron/` (`./existential.sh flow on`) | `services/automation/backup/cron.example/` |
| migrations | `flows/<name>/migrations/` | none |
| runs | everything that reasons, routes, or calls a service API | backups, `triage`, `notes_pull`, `workspace_sync`: bulk mounts and master credentials, no AI |

Each project has its own `inbox/`, `runs/`, `store/`, `cron/` and `processed.md`.
The seeded `.gitignore` keeps `workspace/.decree`'s run state (runs, store, inbox,
attention, logs) from syncing; everything else there syncs, and `graph/` is redrawn
by the entrypoint whenever a machine changes. A seeded file is never re-copied, so a
change to a shipped machine reaches a fresh install, not an existing one. A machine both run (`notify`, `clean_runs`) is one file copied into
both `machines/`; `./existential.sh test decree` fails if the copies differ.
**`/repo` is mounted only into `automation-backup`**: `automation` hands what it
reads to a model, so what it can read is what a prompt injection can read.

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
  `workspace/.decree/.env` so it never syncs; `.env.example` is the template). Secrets come from compose `environment:`, which wins over it. Shared code is in `automation/lib/`
  (`$DECREE_LIB`); state a machine keeps between runs is in `$DECREE_STORE`,
  declared under the machine's `store:`.
- **A migration waits for its own service** in a first `wait_for_<service>` state.
  There is no gate: the entrypoint is `exec decree daemon`, which runs migrations
  in order, and a failed one blocks the rest until `decree process --retry`.
- **One way to reach a model:** `automation/lib/model.sh` (`model_chat`, `model_gate`)
  over the role's OpenAI-compatible `/v1` URL. hermes is optional, through
  `automation/lib/hermes.sh` (`hermes_chat`, `hermes_profile_url`), built on it.
  No container installs an AI CLI.

## Around the daemons

- **Webhook:** `automation-webhook` (its own folder and flag, an add-on outside Core;
  everything it triggers also runs from code-server's terminal) runs decree-go-rest with its daemon off, over
  the `automation` project (read-only, `inbox/` writable). Endpoints are
  `workspace/.decree/decree-go-rest.yml` (seeded from `automation/`); edits load
  without a restart. Hermes gets the `/hermes/*` endpoints on its own secret.
- **Whoever can write `workspace/` can write automations.** That is the point
  (the user directs agents to), and it means every agent with the workspace
  mounted, hermes included, can add a script the `automation` daemon runs with
  its credentials. Keep secrets out of `workspace/` for the same reason.
- **What hermes knows:** `routines_snapshot` copies `graph/system.md`, the
  machines and the endpoints into `workspace/ai/decree/`.
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
  covers only `automation-backup`, so nothing is sent twice. Tested by
  `src/test/unit/test-attention-notify.sh`.
- **Activating a cron** is copying its template into that project's `cron/`.
  Cron files are re-read every tick, so no restart. Six are on by default, copied by
  `exist.initial.sh` whenever the active copy is missing: `triage`, `clean-runs` and
  `workspace-sync` in `automation-backup`, and `you-were-here` (the morning digest),
  `look-back-weekly` and `look-back-monthly` in `automation`.
- **Gate:** `./existential.sh test decree` assembles each project with every
  shipped template queued and runs `decree check`, then diffs the committed
  `graph/`. After changing a machine, run `./existential.sh run decree-graph`.
