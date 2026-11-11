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
[decree](https://github.com/jtmckay/decree) 0.5. This page is how this stack uses it. Worked
example: [Note → Action](../flows/note-to-action.md).

## The file

`clean_runs` is the shortest one to read beside this page:

```markdown
---
machine: plugin
automation: my_job
chart:                   # the decree machine, without its name
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
scripts:                 # each becomes .decree/scripts/my_job/<script>.sh
  my_job: |
    #!/usr/bin/env bash
    # my_job — one line on what it does.
    #
    # This header is the documentation. Say what has to exist first, what it
    # writes and where, and the failure that will confuse the next person.
    set -euo pipefail
    echo "Doing the thing with ${DECREE_DATA_MY_PARAM}"
cron:                    # optional: its schedule, installed with it
  my_job: |
    ---
    machine: my_job
    cron: "0 * * * *"
    ---
---
# my_job

What it does, for a person reading the list.
```

- **`automation:`** is the plugin's name and the file's. Names are snake_case.
- **`chart:`** starts with one state. Add more only when a run shows the need.
- **`data:`** holds the settings. **Every param a message may pass must be declared here**, with
  a default. An undeclared param fails the run and names the key. A message's
  `params:` reach the script as `DECREE_DATA_<NAME>`; the message itself is at
  `$DECREE_MESSAGE`.
- **`needs:`** names the plugins it runs, emits to, or whose lib it uses. You don't write it:
  export does.

Every key, `lib:` and `endpoints:` included: [Plugins](./index.md).

## Turning it on

```bash
./existential.sh run plugin on my_job        # into plugins.yml, installed now
./existential.sh run plugin off my_job       # removed, schedule and endpoints included
```

`plugin on` installs it, and every `./existential.sh` after installs the file's current
version. A machine for `automation-backup` is `backup/my_job`; one for the host is `host/my_job`.

## Changing it live, then committing

Edit the installed copy in `workspace/.decree/` (`machines/my_job.yml`, `scripts/my_job/`) until a
run does what you want, then write it back:

```bash
./existential.sh run plugin export my_job    # → automation/plugins/my_job.md
```

Commit and push. Every install that has it on gets the new version on its next pull. A
machine you only ever write in `workspace/.decree/` works too; it is just never shipped or
updated.

## The script

- **`set -euo pipefail`, always.** Exit 0 is `done`; anything else is `failed`.
- **A failed run notifies you**, with the command that continues it
  ([When a run needs you](../decree/decree.md#when-a-run-needs-you)).
- To retry a flaky step, give that state attempts:
  `invoke: { script: { name: my_job, attempts: 3 } }`.
- A value a machine keeps between runs goes in `$DECREE_STORE`, declared under its `store:`.
- Helpers live in `$DECREE_LIB` (`workspace/.decree/lib/`), each some plugin's `lib:`.

To ask a model, add `model` to what it uses: source `$DECREE_LIB/model.sh` and call
`model_chat <system> <user>`, or `model_gate <criteria> <text>` for yes/no. It uses the role's
`/v1` URL. For an agent with tools on that same model, source `pi.sh` and call
`pi_run <department> <system> <prompt>` ([pi](../ai/pi.md)); for Claude, `agent.sh`. Export
adds each to `needs:`, so turning yours on turns them on.

:::warning[Which daemon?]
- **`automation`** (`workspace/.decree`): anything that reasons, routes, calls a service API or
  runs a migration. It has the model endpoints, pi and Claude.
- **`automation-backup`** (`services/automation-backup/`, off by default): anything that needs
  all of `volumes/` or the master `.env` (backups, `triage`, `notes_pull`). Never an AI call.
- A job that needs both is two machines.
:::

## Choosing a trigger

A machine nothing points at never runs.

### Cron — on a schedule

The plugin's `cron:` installs with it. For one of your own, put a file in
`volumes/workspace_data/.decree/cron/<name>.md` (code-server: `/workspace/.decree/cron/`). No
restart needed:

```markdown
---
cron: "0 * * * *"
machine: my_job
params:
  MY_PARAM: something
---

What this schedule is for. The body is free text.
```

### Webhook — when something out there happens

`automation-webhook` (add-on, `EXIST_IS_SERVICES_AUTOMATION_WEBHOOK`) turns an authenticated POST
into a message. The plugin's `endpoints:` are added while it is installed; one of your own goes
in `workspace/.decree/decree-go-rest.yml`. No restart. See [Over HTTP](./http.md).

### A file landing in Nextcloud — when a file shows up

Upload event → webhook → `file_router` → your **file processor**, a script in
`workspace/.decree/lib/file-processors/` that declares what it matches:

```bash
PATTERN="^nextcloud:workspace/.*\.md$"
CRITERIA="an open question the author has not resolved"
```

`PATTERN` is a path regex; optional `CRITERIA` adds a one-call model check on the content. No
restart needed. To ship one, put it in a plugin's `lib:` (`ocr` and `transcribe` are examples).
See [File Change Processing](../decree/file-change-processing.md).

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

To fan out, emit more than once. Export adds `agent_task` to `needs:`.

## Making it a flow

A flow is a plugin with no machine, in `automation/plugins/flows/<name>.md`: a `name`, a
`tagline`, the `services` it uses, the plugins it `needs:`, and what is left for a person to do.
That is what [`./existential.sh flow`](../flows/index.md) lists. Add a row for it to the
[flows table](../flows/index.md#turning-one-on).

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
| No run at all | Nothing triggers it, or it is not on: `./existential.sh run plugin on <name>` |
| A `failed` run with `invalid_message` | The message names a machine that project does not have, or a param its `data:` does not declare |
| A chained job never runs | The emitting script's `decree emit` failed; its log says why |
| Runs, ends `done`, does nothing | Missing `set -euo pipefail`, so a failed step was swallowed |

## Where to go next

- [Plugins](./index.md): every key, which ones you have, sharing between stacks
- [Note → Action](../flows/note-to-action.md): four machines in one flow
- [File Change Processing](../decree/file-change-processing.md): the file trigger
- [Routing to Departments](../decree/routing.md): sending work to a department
- [Over HTTP](./http.md): the contract for reaching the stack from outside
