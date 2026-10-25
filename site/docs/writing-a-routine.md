---
sidebar_position: 6
---

# Writing an Automation

Every automation in this stack is the same three things: **a script** (bash that does one job),
**a machine** (a few lines of YAML naming the script and its settings), and **a trigger**
(something that decides when to run it). Once you can write one of each, the rest of this
section is detail.

The engine is [decree](https://github.com/jtmckay/decree) 0.5. Its own README covers everything
it can do. This page is how this stack uses it. To watch it used end to end on a real problem,
read [Note → Action](./flows/note-to-action) alongside it.

## The shape of every message

Before the script, the thing it receives. Decree has exactly one message format, and every
trigger produces it:

```markdown
---
machine: note_triage
params:
  TRIAGE_CRITERIA: "a business idea"
---

Anything down here is the body.
```

`machine:` is the only required key. Each key under `params:` reaches the script as
`DECREE_DATA_<NAME>`, and the message itself is at `$DECREE_MESSAGE`. A cron file, a webhook
POST, a message another machine emitted, `decree emit` by hand — they all end up as this.

## The machine

A machine lives in `workspace/.decree/machines/<name>.yml` (on the host,
`volumes/workspace_data/.decree/`), next to your notes, and its graph is redrawn in
`workspace/.decree/graph/` as soon as you save it. To ship one with the repo, put it
in `automation/machines/` instead: each shipped file is copied into a workspace that lacks it,
and never again, so your edits win. Names are snake_case. Start with the
simplest one, a single state, and add states only when a real run shows the need:

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

`data:` is the settings block. **Every param a message may pass must be declared here**, with a
default. Decree fails a run that passes anything else, so a typo in a cron file is a failed run
that names the key, not a setting silently ignored.

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

Three things in there are load-bearing:

- **`set -euo pipefail`, always.** Exit 0 is `done`; anything else is `failed`. A script that
  swallows its own errors and exits 0 reports success for work it never did.
- **It must be executable** (`chmod 755`). Decree runs scripts by path, and `decree check`
  refuses one without the bit.
- **A failed run pages you.** A run that fails, or waits for a person, sends one ntfy message
  naming the machine and the command that continues it
  ([When a run needs you](./decree/decree.md#when-a-run-needs-you)). Nothing to wire up.

To retry a flaky step, give that state attempts: `invoke: { script: { name: my_job, attempts: 3 } }`.
Shared bash and TypeScript helpers are in `automation/lib/` (`$DECREE_LIB`), and a value a
machine keeps between runs goes in `$DECREE_STORE`, declared under the machine's `store:`.

To ask a model, source `$DECREE_LIB/model.sh` and call `model_chat <system> <user>` (or
`model_gate <criteria> <text>` for a yes/no). It talks to the role's OpenAI-compatible `/v1` URL
(`EXIST_MODEL_URL`), so ollama, llama.cpp or a box elsewhere all answer it, and it needs no hermes.
A step that needs an agent with tools uses `hermes.sh` instead, and only when hermes is enabled.

:::warning[Which daemon?]
There are two, and each is its own decree project: **`automation`** (`workspace/.decree`) and
**`automation-backup`** (`services/automation/backup/`, with its own `machines/`, running the
repo's `automation/scripts/`). Both use the repo's `automation/lib/`.

`automation` is where anything that **reasons, routes, calls a service API, or runs a service's
one-time migrations** belongs. It alone has the model endpoints and, when hermes is enabled, its
gateway credential.

`automation-backup` is where anything that needs **bulk volume data or every credential at
once** belongs: it alone mounts `volumes/` wholesale and takes the master `.env`. It is not
backups-only (`notes_pull` and `triage` live there for that access). What it must never do is
reason, route, or make an AI call.

A job that wants an AI *and* bulk volume access is a job that should be two machines.
:::

## Choosing a trigger

A machine that nothing points at never runs. There is no list to register it in.

### Cron — on a schedule

Add a file to `automation-examples/cron/<name>.md` (tracked), then copy it into
`volumes/workspace_data/.decree/cron/` (active). The daemon rescans the directory every tick, so there is
nothing to restart:

```markdown
---
cron: "0 * * * *"
machine: my_job
params:
  MY_PARAM: something
---

What this schedule is for. The body is free text.
```

```bash
cp automation-examples/cron/my-job.md volumes/workspace_data/.decree/cron/
```

The copy-to-activate split is deliberate: examples ship for everyone, and nothing runs on your
machine until you put it in `cron/`.

### Webhook — when something out there happens

`automation-webhook` (the **Capture** add-on) turns an authenticated HTTP POST into a message. Endpoints are configuration
only: add one to `automation/decree-go-rest.yml` and it is live, no restart. This is how Home
Assistant, a phone shortcut, or any external service reaches the stack. See
[Build On It](./build-on-it) for the request contract.

### A file landing in Nextcloud — when a file shows up

Nextcloud fires an event on every upload → the webhook → `file_router` → your **file
processor**. A processor is a small script in `automation/lib/file-processors/` that declares what
it matches:

```bash
PATTERN="^nextcloud:workspace/.*\.md$"
CRITERIA="an open question the author has not resolved"
```

`PATTERN` is a path regex; the optional `CRITERIA` adds a one-call model gate so you match on
*content* rather than filename. No restart needed — the router reads the directory per event.
Full detail in [File Change Processing](./decree/file-change-processing).

### By hand — for testing, and for one-offs

```bash
echo 'The body.' | docker exec -i automation decree emit --machine my_job --param MY_PARAM=value
```

For `automation-backup`'s machines, `docker exec -i automation-backup` instead.

## Chaining: one machine handing work to the next

This is what turns jobs into flows. A script does not call another script. It **emits a
message** and returns, and decree runs that as its own job, with its own log and its own line in
the dashboard:

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

Fan-out is just emitting more than once.

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

Every run's events and logs also ship to Loki, and Grafana's **Decree Overview** dashboard shows
a new machine with no wiring on your part. After adding or changing a machine, run
`./existential.sh run decree-graph` to regenerate the committed diagrams.

Common reasons a job appears to do nothing:

| Symptom | Cause |
|---|---|
| No run at all | Nothing triggers it: the cron file is in `automation-examples/`, not `volumes/workspace_data/.decree/cron/` |
| A `failed` run with `invalid_message` | The message names a machine that project does not have, or a param its `data:` does not declare |
| A chained job never runs | The emitting script's `decree emit` failed; its log says why |
| Runs, ends `done`, does nothing | Missing `set -euo pipefail`, so a failed step was swallowed |

## Where to go next

- [Note → Action](./flows/note-to-action) — four machines wired into one flow, step by step
- [File Change Processing](./decree/file-change-processing) — the file-trigger path in full
- [Routing to Departments](./decree/routing) — handing work to a specific hermes profile
- [Build On It](./build-on-it) — the HTTP contract, if you are integrating from outside
