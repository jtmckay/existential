# Scripts

A script is any executable file; the shebang picks the language (bash by default). It does one
piece of work, makes no routing decision, and reports one outcome.

## Where scripts live

Machines name scripts, never paths. Script `X` used by machine `M` resolves in one folder only,
`.decree/machines/M/scripts/`. There is no other search path: a script another machine ships is
reached by path from a script, never by name. To share a machine and its scripts across projects, make it a plugin: `decree export M` writes `.decree/plugins/M.md`.

A match is a file named `X` or `X.<ext>` (`verify.sh`), executable, and the only match in its
directory. Script names match `^[a-z][a-z0-9_]*$`. Code several machines share is a library: a
machine folder with no `machine.yml` (a plugin with no `machine`), whose scripts others source
by path and name in their plugin's `needs`.
`chmod +x` new scripts; `decree check` fails otherwise.

A machine's helpers, config and data (bash functions to source, a prompt template, workflow
files) sit beside its scripts in `machines/<machine>/scripts/`; decree runs only a file a state names,
and other files there are never an error. Scripts reach them by path from the project root,
their working directory: `. .decree/machines/decree_develop/scripts/ai.sh`. What a machine keeps between runs
goes in `$DECREE_STATE_DIR`.

`machines/decree_infra/scripts/` holds the project's declared environment. `requirements` lists one resource
per line (`kind name version source`), in dependency order; any other machine may keep a
`requirements` beside its scripts, and every `.decree/machines/*/scripts/requirements` is one list,
decree_infra's first; `kinds/<kind>.sh` defines `check` and
`install` for a kind, each called with the line's name, version and source; `run.sh check`
reports each line `ok` or `missing`, with the file it came from, and `run.sh apply` installs what is missing and checks it
again. A kind installs into the project (a venv, `node_modules`, `.tools/bin`), never with
`sudo`; a step only a person can do prints the exact command and returns 1. A kind that
downloads checks the file against the sha256 in its line's source, `<url>#sha256=<hex>`, taken
from what the project publishes (`SHA256SUMS`, the release page), never from hashing the
download itself. The `decree_infra` plugin ships
the `command` kind (on `PATH`, at the line's version if it has one, from `--version`; or a
person installs it).

## How a script runs

- Directly (no shell wrapper), from the project root, with stdin `/dev/null`, in its own process
  group.
- stdout and stderr go, interleaved and unmarked, to `runs/<id>/NNNN-<state>-<script>.log`
  (`NNNN-<state>.log` when the script is named as its state). What an invoke prints is what a later `matches` check or model reads. Output
  is only a log: decree never reads an event from it.
- On stop or timeout, decree sends SIGTERM to the group, then SIGKILL after 10 s.
- Scripts must be safe to re-run: an interrupted or failed step runs again after
  `decree retry`. Check that a result works, not that its file exists: a step that
  failed halfway may have left the file.

## Reporting an event (invoke only)

Write the event's name to `$DECREE_EVENT_FILE`, a fresh empty file for each attempt
(`echo pass > "$DECREE_EVENT_FILE"`; in Python,
`open(os.environ["DECREE_EVENT_FILE"], "w").write("pass")`).

1. Exit non-zero: `error`. The file is not read.
2. Exit 0 and the file holds a name (whitespace trimmed): that event.
3. Exit 0 and the file is empty, or holds `done`: `done`.
4. Any other name that is reserved or matches no transition of the state or its ancestors: `error`.

```bash
#!/usr/bin/env bash
# machines/feature/scripts/verify.sh: a pass is deterministic; only failures go further.
set -uo pipefail
cargo test 2>&1 | tail -n 40
if [ "${PIPESTATUS[0]}" -eq 0 ]; then
  echo pass > "$DECREE_EVENT_FILE"
else
  echo fail > "$DECREE_EVENT_FILE"
fi
```

`onentry` and `onexit` scripts never produce events:

- A failing `onentry` script skips the remaining `onentry` scripts of that state only (SCXML stops
  the failing block, `error.execution`). The other states being entered still run theirs,
  outermost first. Once entry is complete, the event is `error`, selected from the atomic state
  entered like any other event, and the invoke does not run. This holds for root `onentry` too:
  an `error` transition can handle it, and otherwise it goes to `failed`.
- A failing `onentry` script on a root-level final state moves the run to `failed` instead of
  ending in that state, so a failed `commit` is never reported as `done`.
- A failing `onexit` script is recorded in the `transition` event under `exit_failures`; the event
  and target do not change.

`$DECREE_EVENTS` lists the events the current state accepts.

## Queueing follow-up work

```bash
#!/usr/bin/env bash
# machines/feature/scripts/spawn.sh: the state lists `emits: [feature]`.
set -euo pipefail
decree emit --machine feature <<'EOF'
# Follow-up: split rate limiting per route

## Overview
## Outcome
## Constraints
## Acceptance Criteria
EOF
```

## Run-directory files

Scripts hand work to one another, and to a person, through files in `$DECREE_ROOT_RUN_DIR`
(the run's own folder, or in a child run of a `machine` invoke its root run's, so a child
machine whose steps are decree_develop's scripts shares them; an emitted message and an
order file's run each start their own work and have their own). decree reads none of them but `hold`, and quotes `STOP` and
`leftovers` in the run's attention file; the official `decree_develop` plugin's scripts follow this convention:

- `progress.md`: the step log, one line per step, what is done and what is next. A retry
  reads it and continues.
- `STOP`: a question instead of a guess. A script that finds it prints it and writes `stop` to
  `$DECREE_EVENT_FILE`; it keeps stopping retries until a person answers in `plan.md`, deletes
  it and runs `decree retry`.
- `gate.log`: the output of the project's checks (`machines/decree_develop/scripts/gate.sh`), for the step that
  fixes them. The gate names `pass` or `fail`; a non-zero exit (`error`) means the checks could
  not run, such as a missing tool, and its message is here.
- `plan.md`: a plan for later steps, and a person's answer to a `STOP`. decree_develop's AI steps read it.
- `gaps.md`: what `verify` found missing on `fail`; a retry's `implement` closes each first.
  `verify` keeps the last one if an attempt dies.
- `hold`, in the run's own `$DECREE_RUN_DIR`: written by a step whose failure must stop the
  runs that share its machine's group (the official plugins' `keep`, in `failed`). decree puts
  its text in the run's file in `.decree/attention/` with `holds: true`, and no run of that
  group runs until `decree retry <id>` removes both or a person deletes the attention file.
- `leftovers`, in the run's own `$DECREE_RUN_DIR`: written by the official plugins' `clean_tree` when it
  finds uncommitted changes. It names each run that passed `clean_tree` and is now
  `interrupted` or `failed` (from `"${DECREE}" status --all --format json`, read with `jq`),
  with `decree retry <id>` and `git stash push --include-untracked -m "decree <id>"
  -- .`; `clean_tree` prints the same lines. decree quotes it in the run's attention file.

## Environment

| Variable | Value |
| --- | --- |
| `DECREE` | The decree executable running the script; call it as `"${DECREE}"`, not `decree`, which may not be on `PATH`. |
| `DECREE_PROJECT_ROOT` | Directory containing `.decree/`. |
| `DECREE_MESSAGE` | `runs/<id>/message.md` (the run's copy of the message). |
| `DECREE_MESSAGE_ID` | The message `id`. |
| `DECREE_MACHINE`, `DECREE_STATE` | Machine and state (`_root` for root `onentry`/`onexit`). |
| `DECREE_PHASE` | `onentry`, `invoke` or `onexit`. |
| `DECREE_VISITS` | Times this state has been entered, including now, since the run's last retry. |
| `DECREE_RUN_ATTEMPT` | The run's attempt: 1, then one more per `decree retry`. |
| `DECREE_RUN_DIR` | `runs/<id>/`. |
| `DECREE_STATE_DIR` | `.decree/machines/<machine>/state/`: what this machine keeps between runs; created before the script runs. |
| `DECREE_ATTEMPT`, `DECREE_MAX_ATTEMPTS`, `DECREE_FINAL_ATTEMPT` | Attempt number, the limit, and `true` on the last one. |
| `DECREE_ATTEMPT_VALUE`, `DECREE_ATTEMPT_VALUES` | With an `attempts` list: this attempt's entry, and the whole list, space-separated. Unset with `attempts: <n>`; no value for `onentry`/`onexit`. |
| `DECREE_TRIGGER` | `cron`, `emit`, `inbox` or `invoke`. |
| `DECREE_EVENTS` | Events the current state accepts, space-separated. |
| `DECREE_EVENT_FILE` | For an invoke: the file to write its event to. Empty for other scripts. |
| `DECREE_PARENT` | In a child run, the parent run's id. |
| `DECREE_PARENT_RUN_DIR` | In a child run, the parent run's folder; empty otherwise. Reach the task's files from here, never by building `runs/$DECREE_PARENT`. |
| `DECREE_ROOT_RUN_DIR` | The root run's folder: a `machine` invoke's child shares its parent's; a top-level run, an emitted message and an order file's run are their own root (`DECREE_RUN_DIR`). |
| `DECREE_REQUEST`, `DECREE_REPLY` | In a router run: the request JSON to read and the reply JSON to write. |
| `DECREE_WAIT_ID`, `DECREE_QUESTION`, `DECREE_CHOICES` | For a `reply` state's `notify` script: the wait id, the question, and a JSON file of options and descriptions. |
| `DECREE_RECEIVED` | The last reply this run received (`runs/<id>/received/<file>`), or empty. |
| `DECREE_DATA_<NAME>` | Each `data` value: the message's `params`, else the default. |
| `TRACEPARENT`, `TRACESTATE` | W3C Trace Context: the run's trace and this script's span (`00-<trace id>-<span id>-01`), and the message's `tracestate` if it had one. OpenTelemetry SDKs read them, so the script's own spans join the run's trace; `decree emit` copies them into the new message. |

Variables and secrets (an API key, a service URL, a model name) go in dotenv files in
`.decree/`, which `.decree/.gitignore` keeps out of git with `.env*`:

- `.decree/.env`: every script gets it. The process environment wins over it.
- A machine's `env_file: .env.<name>`: that machine's scripts get it, over `.decree/.env` and
  the process environment. A child machine, router or emitted message runs with its own
  machine's file, never this one's.
- `.decree/.env.example`: the committed template; decree never reads it.

Format: `KEY=value` per line, `#` comments, optional `export ` and quotes. Values are
interpolated as Compose's `env_file` does: `${VAR}`, `$VAR`, `${VAR:-default}`,
`${VAR-default}`, `$$` for a `$`; single-quoted values stay literal. Write a shared host once:
`HOST=box` then `COMFY_URL=http://${HOST}:8188`. An unknown variable is empty and
`decree check` warns. Never source them by hand. `DECREE_*`, `TRACEPARENT` and `TRACESTATE`
cannot be set in them, except `DECREE_MACHINES` and `DECREE_EXCLUDE_MACHINES` in `.decree/.env`,
which pick the machines `daemon` run and never reach scripts, and
`DECREE_MAX_DEPTH` (default 10), the deepest chain of emits and child runs. When two set a name, the first wins: decree's own `DECREE_*`, the
machine's `env_file`, the process environment, `.decree/.env`.

One script run by several states with different values: give each state a two-line script,
`METHOD=image_text exec "$(dirname "$0")/build.sh"`, rather than parsing the state name.

## A notify script

```bash
#!/usr/bin/env bash
# scripts/notify_person.sh: tell someone how to answer. A real one posts to chat or opens an issue.
set -euo pipefail
echo "Question: $DECREE_QUESTION"
cat "$DECREE_CHOICES"
for event in $DECREE_EVENTS; do
  [ "$event" = error ] && continue
  echo "  decree reply $DECREE_WAIT_ID $event -m \"<note>\""
done
```

## Long-running services

Model servers and similar services are not scripts; run them under systemd or similar. A state
that needs one starts it in a quick `onentry` script (`systemctl --user start comfyui`), so the
dependency shows in the machine and its graph. Waiting until it is ready is an invoked state
with a `timeout`, since `onentry` has none.
