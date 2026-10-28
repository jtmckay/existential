---
sidebar_position: 6
---

# Writing an Automation

An automation is three things:

- **a script**: bash that does one job
- **a machine**: a few lines of YAML naming the script and its settings
- **a trigger**: what decides when it runs

The engine is [decree](https://github.com/jtmckay/decree) 0.5. This page is how this stack uses
it. Worked example: [Note → Action](./flows/note-to-action).

## The shape of every message

Every trigger produces the same message format:

```markdown
---
machine: note_triage
params:
  TRIAGE_CRITERIA: "a business idea"
---

Anything down here is the body.
```

`machine:` is the only required key. Each `params:` key reaches the script as
`DECREE_DATA_<NAME>`; the message is at `$DECREE_MESSAGE`.

## The machine

- Lives in `workspace/.decree/machines/<name>.yml` (host: `volumes/workspace_data/.decree/`). Its
  graph in `workspace/.decree/graph/` is redrawn on save.
- To ship one with the repo, put it in `automation/machines/`; it's copied into a workspace once.
- Names are snake_case. Start with one state; add more only when a run shows the need.

```yaml
name: my_job
description: One line on what it does; hermes and the graph both show it.
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
```

`data:` holds the settings. **Every param a message may pass must be declared here**, with a
default. An undeclared param fails the run and names the key.

## The script

`invoke: my_job` runs `scripts/my_job.sh` in the same project. `service_health.sh` is a good short one to
read next to this:

```bash
#!/usr/bin/env bash
# my_job — one line on what it does.
#
# This header is the documentation. Say what has to exist first, what it writes
# and where, and the failure that will confuse the next person.
set -euo pipefail

MY_PARAM="$DECREE_DATA_MY_PARAM"
MY_LIMIT="$DECREE_DATA_MY_LIMIT"

echo "Doing the thing with ${MY_PARAM}"
```

- **`set -euo pipefail`, always.** Exit 0 is `done`; anything else is `failed`.
- **It must be executable** (`chmod 755`). Decree runs scripts by path, and `decree check`
  refuses one without the bit.
- **A failed run notifies you**, with the command that continues it
  ([When a run needs you](./decree/decree.md#when-a-run-needs-you)).

To retry a flaky step, give that state attempts: `invoke: { script: { name: my_job, attempts: 3 } }`.
Shared bash and TypeScript helpers are in `automation/lib/` (`$DECREE_LIB`), and a value a
machine keeps between runs goes in `$DECREE_STORE`, declared under the machine's `store:`.

To ask a model, source `$DECREE_LIB/model.sh` and call `model_chat <system> <user>`, or
`model_gate <criteria> <text>` for yes/no. It uses the role's `/v1` URL. For an agent with tools,
use `hermes.sh` (hermes must be enabled).

:::warning[Which daemon?]
- **`automation`** (`workspace/.decree`): anything that reasons, routes, calls a service API or
  runs a migration. It has the model endpoints and hermes credential.
- **`automation-backup`** (`services/automation-backup/`, off by default): anything that needs
  all of `volumes/` or the master `.env` (backups, `triage`, `notes_pull`). Never an AI call.
- A job that needs both is two machines.
:::

## Choosing a trigger

A machine nothing points at never runs.

### Cron — on a schedule

Put a file in `volumes/workspace_data/.decree/cron/<name>.md` (code-server:
`/workspace/.decree/cron/`). No restart needed:

```markdown
---
cron: "0 * * * *"
machine: my_job
params:
  MY_PARAM: something
---

What this schedule is for. The body is free text.
```

To ship one, make it a flow: `flows/<name>/flow.md` plus the cron file in `flows/<name>/cron/`.
`./existential.sh flow on <name>` copies it in.

### Webhook — when something out there happens

`automation-webhook` (add-on, `EXIST_IS_SERVICES_AUTOMATION_WEBHOOK`) turns an authenticated POST
into a message. Add an endpoint to `automation/decree-go-rest.yml`; no restart. See
[Build On It](./build-on-it).

### A file landing in Nextcloud — when a file shows up

Upload event → webhook → `file_router` → your **file processor**, a script in
`automation/lib/file-processors/` that declares what it matches:

```bash
PATTERN="^nextcloud:workspace/.*\.md$"
CRITERIA="an open question the author has not resolved"
```

`PATTERN` is a path regex; optional `CRITERIA` adds a one-call model check on the content. No
restart needed. See [File Change Processing](./decree/file-change-processing).

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

List what a state emits in its machine, so `decree check` validates the params and
`decree graph` draws the chain:

```yaml
  run:
    invoke: my_job
    transitions: { done: done }
    emits: [agent_task]
```

To fan out, emit more than once.

## Verifying it

```bash
# 1. Is it valid? Checks machines, scripts and every queued message.
./existential.sh test decree

# 2. Run it for real
echo | docker exec -i automation decree emit --machine my_job

# 3. Read what happened
docker exec automation decree status          # runs by state; failed ones say how to retry
docker exec automation decree status <id>     # one run's events
ls volumes/workspace_data/.decree/runs/<id>/                      # message.md, events.jsonl, one log per script
```

With Monitoring on, runs also go to Loki and Grafana's **Decree Overview**. After changing a
shipped machine, run `./existential.sh run decree-graph`.

Why a job seems to do nothing:

| Symptom | Cause |
|---|---|
| No run at all | Nothing triggers it: the cron file is in `flows/`, not `volumes/workspace_data/.decree/cron/` — `./existential.sh flow on <name>` |
| A `failed` run with `invalid_message` | The message names a machine that project does not have, or a param its `data:` does not declare |
| A chained job never runs | The emitting script's `decree emit` failed; its log says why |
| Runs, ends `done`, does nothing | Missing `set -euo pipefail`, so a failed step was swallowed |

## Where to go next

- [Note → Action](./flows/note-to-action): four machines in one flow
- [File Change Processing](./decree/file-change-processing): the file trigger
- [Routing to Departments](./decree/routing): sending work to a hermes profile
- [Build On It](./build-on-it): the HTTP contract
