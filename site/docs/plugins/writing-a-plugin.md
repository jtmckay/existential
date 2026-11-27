---
sidebar_position: 2
---

# Writing a Plugin

An automation is three things:

- **a script**: bash that does one job
- **a machine**: a few lines of YAML naming the script and its settings
- **a trigger**: what decides when it runs

A plugin is all three in one file, `automation/plugins/<name>.md`, so it can be committed, turned
on and kept current like every automation the stack ships. The engine is
[decree](https://github.com/jtmckay/decree) 0.6, and a plugin is
[decree's plugin file](https://github.com/jtmckay/decree/blob/main/docs/reference/plugins.md), with
this stack's own keys named `x-exist-…`. This page is how this stack uses it. Worked
example: [Note → Action](./note-to-action.md).

## The file

`boot_daemon` is the shortest one to read beside this page:

```markdown
---
name: my_job
machine:                 # the decree machine, without its name
  description: One line on what it does.
  data:
    MY_PARAM: { type: string, default: a default }
    MY_LIMIT: { type: int, default: 20 }
  initial: run
  states:
    run:
      invoke: my_job
      transitions: { done: done }
    done: { final: true }
    failed: { final: true }
scripts:                 # each becomes .decree/machines/my_job/scripts/<file>
  my_job.sh: |
    #!/usr/bin/env bash
    # my_job — one line on what it does.
    #
    # This header is the documentation. Say what has to exist first, what it
    # writes and where, and the failure that will confuse the next person.
    set -euo pipefail
    echo "Doing the thing with ${DECREE_DATA_MY_PARAM}"
cron:                    # optional: its schedule, installed with it once
  my_job.md: |
    ---
    machine: my_job
    cron: "0 * * * *"
    ---
x-exist-project: automation
---
# my_job

What it does, for a person reading the list.
```

- **`name:`** is the plugin's name and the file's. Names are snake_case.
- **`machine:`** starts with one state. Add more only when a run shows the need.
- **`data:`** holds the settings. **Every param a message may pass must be declared here**, with
  a default. An undeclared param fails the run and names the key. A message's
  `params:` reach the script as `DECREE_DATA_<NAME>`; the message itself is at
  `$DECREE_MESSAGE`.
- **`needs:`** names the plugins it runs, emits to, or whose lib it uses. `decree export` writes
  the machines it invokes or emits to; add a lib it sources (`model`) yourself.

Every key, `x-exist-lib:` and `x-exist-endpoints:` included: [Plugins](./index.md).

## Turning it on

```bash
./existential.sh plugin on <name>        # into its project's list (.decree/plugins/.on), installed now
./existential.sh plugin off <name>       # removed, schedule and endpoints included
```

`plugin on` installs it, and every `./existential.sh` after installs the file's current
version. Where it is installed is its `x-exist-project` key: `automation` (the default to write),
`backup` for `automation-backup`, or `host` for the host's daemon.

## Changing it live, then committing

On the host, edit the installed copy in `volumes/workspace_data/.decree/machines/my_job/`
(`machine.yml`, `scripts/`) until a run does what you want, then write it back. The same folders are
writable in code-server, where `decree install <name>` reinstalls from the plugin file.

```bash
./existential.sh plugin export my_job    # → automation/plugins/my_job.md
```

Commit and push. Every install that has it on gets the new version on its next pull.

## The script

- **`set -euo pipefail`, always.** Exit 0 is `done`; anything else is `failed`.
- **A failed run notifies you**, with the command that continues it
  ([When a run needs you](../decree/decree.md#when-a-run-needs-you)).
- To retry a flaky step, give that state attempts:
  `invoke: { script: { name: my_job, attempts: 3 } }`.
- A value a machine keeps between runs goes in `$DECREE_STATE_DIR`, declared under its `state_files:`.
- Helpers live in `workspace/.decree/lib/`, each some plugin's `x-exist-lib`; a script runs in
  the project's root, so it sources one as `.decree/lib/<path>`.

To ask a model, add `model` to what it uses: source `.decree/lib/model.sh` and call
`model_chat <system> <user>`, or `model_gate <criteria> <text>` for yes/no. It uses the role's
`/v1` URL. For an agent with tools on that same model, source `pi.sh` and call
`pi_run <department> <system> <prompt>` ([pi](../ai/pi.md)); for Claude, `agent.sh`. Add each to
`needs:`, so turning yours on turns them on.

:::warning[Which daemon?]
- **`automation`** (`workspace/.decree`): anything that reasons, routes, calls a service API or
  runs one-time setup (an order file). It has the model endpoints, pi and Claude.
- **`automation-backup`** (`services/automation-backup/`, off by default): anything that needs
  all of `volumes/` or the master `.env` (backups, `triage`, `notes_pull`). Never an AI call.
- A job that needs both is two machines.
:::

## Choosing a trigger

A machine nothing points at never runs.

### Cron — on a schedule

The plugin's `cron:` installs with it. To run an installed machine on a schedule of your own,
write a plugin that holds only cron files, each naming the machine it runs, and
[install it](./offer-and-accept.md). No restart needed:

```markdown
---
name: my_schedules
needs: [my_job]
cron:
  my-job-hourly.md: |
    ---
    cron: "0 * * * *"
    machine: my_job
    params:
      MY_PARAM: something
    ---

    What this schedule is for. The body is free text.
---
# my_schedules

Why these run when they do.
```

To change one later, offer the plugin again with the new file and accept it.

### Webhook — when something out there happens

`automation-webhook` (add-on, `EXIST_IS_SERVICES_AUTOMATION_WEBHOOK`) turns an authenticated POST
into a message. The plugin's `x-exist-endpoints` are added while it is installed; one of your own goes
in `workspace/.decree/decree-go-rest.yml`. No restart. See [Over HTTP](./http.md).

### A file landing in Nextcloud — when a file shows up

Upload event → webhook → `file_router` → your **file processor**, a script in
`workspace/.decree/lib/file-processors/` that declares what it matches:

```bash
PATTERN="^nextcloud:workspace/.*\.md$"
CRITERIA="an open question the author has not resolved"
```

`PATTERN` is a path regex; optional `CRITERIA` adds a one-call model check on the content. No
restart needed. To ship one, put it in a plugin's `x-exist-lib` (`ocr` and `transcribe` are examples).
See [File Change Processing](./file-change-processing.md).

### By hand — for testing, and for one-offs

```bash
echo 'The body.' | docker exec -i automation decree emit --machine my_job --param MY_PARAM=value
```

For `automation-backup`'s machines, `docker exec -i automation-backup` instead.

## Chaining: one machine handing work to the next

A script doesn't call another script. It **emits a message**, and decree runs that as its own
job with its own log:

```bash
echo 'Who else is already doing this?' \
    | decree emit --machine agent_task --param profile=research --param output_name=competition
```

List what a state emits in its machine, so `decree check` validates the params and the graph
draws the chain:

```yaml
    run:
      invoke: my_job
      transitions: { done: done }
      emits: [agent_task]
```

To fan out, emit more than once. `decree export` adds `agent_task` to `needs:`.

## Listing it

A plugin a person turns on is written up where a person looks for it: on the
[What It Does](../flows/index.md) page for the problem it solves, or on the docs page of the
service or host feature it belongs to. That is what it does, its `./existential.sh plugin on`
line (and `service on`, for the services it uses), and what is left for a person to do.
`./existential.sh validate conventions` fails a plugin nothing needs whose `plugin on` line is
on no docs page.

## Verifying it

```bash
# 1. Is it valid? Every plugin, alone and together, through decree check.
./existential.sh test decree

# 2. Run it for real
echo | docker exec -i automation decree emit --machine my_job

# 3. Read what happened
docker exec automation decree status          # runs by state; failed ones say how to retry
docker exec automation decree status <id>     # one run's events
ls volumes/workspace_data/.decree/runs/<id>/  # message.md, events.jsonl, one log per script
```

With Monitoring on, runs also go to Loki and Grafana's **Decree Overview**.

Why a job seems to do nothing:

| Symptom | Cause |
|---|---|
| No run at all | Nothing triggers it, or it is not on: `./existential.sh plugin on <name>` |
| A `failed` run with `invalid_message` | The message names a machine that project does not have, or a param its `data:` does not declare |
| A chained job never runs | The emitting script's `decree emit` failed; its log says why |
| Runs, ends `done`, does nothing | Missing `set -euo pipefail`, so a failed step was swallowed |

## Where to go next

- [Plugins](./index.md): every key, which ones you have, sharing between stacks
- [Note → Action](./note-to-action.md): four machines in one flow
- [File Change Processing](./file-change-processing.md): the file trigger
- [Routing to Departments](./routing.md): sending work to a department
- [Over HTTP](./http.md): the contract for reaching the stack from outside
