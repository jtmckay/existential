---
sidebar_position: 6
---

# Writing a Routine

Every automation in this stack is the same two things: **a routine** (a bash script that does
one job) and **a trigger** (something that decides when to run it). Nothing else. Once you can
write one and pick the other, the rest of this section is detail.

This page is the contract. If you want to watch it used end to end on a real problem, read
[Note → Action](./flows/note-to-action) alongside it — that flow is four routines wired
together and nothing more.

## The shape of every message

Before the script, the thing the script receives. Decree has exactly one message format, and
every trigger produces it:

```markdown
---
routine: note-triage
TRIAGE_CRITERIA: "a business idea"
---

Anything down here is the body.
```

`routine:` is the only required key. **Every other frontmatter key becomes an environment
variable** for the routine, and the body is available at `${message_file}`. A cron file, a
webhook POST, a message another routine wrote, a file you drop in the inbox by hand — they all
end up as this. Learn this one shape and every trigger below is the same trigger.

## Anatomy of a routine

Routines live in `automation/shared_routines/<name>.sh`. The filename minus `.sh` is the
routine name. Here is the whole structure, in order — `service-health.sh` is a good short one
to read next to this:

```bash
#!/usr/bin/env bash
# my-routine — one line on what it does.
#
# Everything in this header block is the documentation. `decree routine
# my-routine` prints it, so write it for the person who has to enable this in
# six months. Say what it needs, what it writes, and how to run it by hand.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Decree sets these for every run.
message_file="${message_file:-}"   # the message that triggered this run
message_id="${message_id:-}"       # e.g. D0001-1432-my-routine-0
message_dir="${message_dir:-}"     # run directory, holds logs from prior attempts
chain="${chain:-}"                 # chain ID, if this run was chained
seq="${seq:-}"                     # position in that chain

# The pre-check. Required. This is the routine's self-test.
if [ "${DECREE_PRE_CHECK:-}" = "true" ]; then
    source "${SCRIPT_DIR}/../lib/precheck.sh"
    command -v jq >/dev/null 2>&1 || precheck_fail "my-routine" "jq not found"
    precheck_pass "my-routine"
    exit 0
fi

# Your settings. This block is special — see below.
my_param="${my_param:-a default}"
MY_LIMIT="${MY_LIMIT:-20}"

# --- Implementation ---

echo "Doing the thing with ${my_param}"
```

Four things in there are load-bearing.

### The header comment is the documentation

There is no separate doc for a routine. `decree routine <name>` prints this block, and it is
what someone reads before enabling your script. Write down the non-obvious parts: what has to
exist first, what it writes and where, and the failure that will confuse them.

### `set -euo pipefail`, always

Decree treats a non-zero exit as failure and retries the message up to `max_attempts`, then
dead-letters it. That retry is only useful if your script actually fails when a step fails.

### The pre-check gate is your self-test

Gate it on `DECREE_PRE_CHECK=true`, put it **after** the standard variables and **before** your
own settings, and exit non-zero with a message naming what is missing. `precheck_fail` in
`automation/lib/precheck.sh` formats it consistently.

This is what `docker exec automation decree routine <name>` runs, and it is the fastest way to find
out why an automation is quietly doing nothing. Check for the things that are actually absent
in a fresh install — a missing binary, an unset key, a directory the upstream routine was
supposed to create — and say in the message how to fix it, not just what is wrong:

```bash
[ -d "${NOTES_DIR:-/data/notes}" ] || precheck_fail "note-triage" \
    "NOTES_DIR ${NOTES_DIR:-/data/notes} does not exist — run the 'notes' routine first, or point NOTES_DIR at your vault"
```

### Settings must be one unbroken block

Decree discovers your routine's parameters by scanning the file top to bottom and matching the
exact form `name="${name:-default}"`. It **stops at the first line that does not match** after
the pre-check block.

So this works:

```bash
FOO="${FOO:-1}"
BAR="${BAR:-2}"
```

and this silently loses `BAR`:

```bash
FOO="${FOO:-1}"
echo "starting"          # ← scanning stops here
BAR="${BAR:-2}"          # ← never settable from frontmatter
```

Put every setting in one run of lines directly after the pre-check, then start the
implementation. `${VAR:-}` with an empty default is fine — it means optional, no default.

## Registering it

A routine on disk is invisible until it is listed. Every daemon has a
`<category>/<slug>/decree/config.exist.yml` with a `shared_routines:` whitelist:

```yaml
shared_routines:
  my-routine:
    enabled: true
```

- **Unlisted means invisible.** Not disabled — absent.
- `enabled: false` means the routine is known and off. That is the right default for anything
  opt-in; the user flips it on.
- Add it to **every** daemon that should see it. Sidecars each have their own config.
- `config.exist.yml` is the tracked template. `./existential.sh` renders it once to
  `config.yml`, which is gitignored and is where the user's own overrides live — so edit the
  template *and*, if `config.yml` already exists, the rendered copy too.

:::warning[Which daemon?]
There are two, and they are not interchangeable. `decree` is where anything that reasons,
routes, calls a service API or writes to `workspace/` belongs — it alone has a writable
`/workspace` and the read-only `/repo` mount. `decree-backup` is where anything that reads
volume data belongs — it alone mounts `volumes/` and carries every service's credentials, and
it deliberately has no AI CLI installed. A routine that needs both is a routine that should be
two.
:::

## Choosing a trigger

Four ways in. All of them produce the same message.

### Cron — on a schedule

Add a file to `automation-examples/cron/<name>.md` (tracked), then copy it into
`automation/cron/` (active, gitignored, mounted into the daemon) and restart it:

```markdown
---
cron: "0 * * * *"
routine: my-routine
my_param: "something"
---

What this schedule is for. The body is free text.
```

```bash
cp automation-examples/cron/my-routine.md automation/cron/
docker compose restart automation
```

The copy-to-activate split is deliberate: examples ship for everyone, and nothing runs on your
machine until you put it in `cron/`. Frontmatter is parsed on restart, so changing a setting
means restarting the daemon.

### Webhook — when something out there happens

`automation-webhook` turns an HTTP POST into an inbox message. Endpoints are configuration only —
add one to `services/automation/webhook/config.exist.yml`, re-render, restart. Each carries its own
bearer token. This is how Home Assistant, a phone shortcut, or any external service reaches the
stack. See [Build On It](./build-on-it) for the request contract.

### An object landing in storage — when a file shows up

MinIO fires an event on write → the webhook → `minio-router` → your **file processor**. A
processor is a small script in `automation/lib/file-processors/` that declares what it matches:

```bash
PATTERN="minio:workspace/.*\.md$"
CRITERIA="an open question the author has not resolved"
```

`PATTERN` is a path regex; the optional `CRITERIA` adds a one-call model gate so you match on
*content* rather than filename. No restart needed — the router reads the directory per event.
Full detail in [File Change Processing](./decree/file-change-processing).

### By hand — for testing, and for one-offs

```bash
docker exec automation decree run my-routine
docker exec automation decree run --routine my-routine --param my_param=value
```

Or drop the message file yourself:

```bash
printf -- '---\nroutine: my-routine\n---\n' > services/automation/decree/inbox/once.md
```

## Chaining: one routine handing work to the next

This is what turns routines into flows. A routine does not call another routine — it **writes a
message** and returns. Decree picks it up and runs it as its own job, with its own retries, its
own log and its own line in the dashboard.

```bash
OUTBOX_DIR="${OUTBOX_DIR:-/work/.decree/outbox}"
mkdir -p "$OUTBOX_DIR"

cat > "${OUTBOX_DIR}/handoff-$(date +%s%N).md" <<MSG
---
routine: hermes-dept
profile: research
output_name: competition
---
Who else is already doing this?
MSG
```

Three rules:

- **Write to the outbox, never the inbox.** Decree relays outbox → inbox itself. Writing
  straight to the inbox races the daemon.
- **`mkdir -p "$OUTBOX_DIR"` first.** Decree reads the outbox but never creates it, and an
  absent directory is silently treated as "no messages" — your handoff disappears with no error.
- **Unique filenames.** `$(date +%s%N)` is what the shipped routines use. Two messages written
  in the same second must not collide.

Fan-out is just writing more than one message. Chains are bounded by `max_depth` (100), so a
routine that queues itself will stop rather than run forever.

## Verifying it

```bash
# 1. The pre-check — does it think it can run?
docker exec automation decree routine my-routine

# 2. Run it for real
docker exec automation decree run my-routine

# 3. Read what happened
ls automation/runs/                       # one directory per message
cat automation/runs/<id>/run.json         # status, timing, exit code
cat automation/runs/<id>/routine.log      # full output, written live
```

Every run also ships metrics to Prometheus and its log to Loki automatically — the `afterEach`
hook does it, so a new routine shows up in Grafana's **Decree Overview** dashboard with no
wiring on your part.

Common reasons a routine appears to do nothing:

| Symptom | Cause |
|---|---|
| No run directory at all | Not listed in that daemon's `config.yml`, or `enabled: false` |
| Cron never fires | File is in `cron.example/`, not `cron/` — or the daemon wasn't restarted |
| A frontmatter setting is ignored | It is below a non-matching line in the settings block |
| A chained routine never runs | Wrote to the inbox instead of the outbox, or `$OUTBOX_DIR` didn't exist |
| Runs, exits 0, does nothing | Missing `set -euo pipefail`, so a failed step was swallowed |

## Where to go next

- [Note → Action](./flows/note-to-action) — four routines wired into one flow, step by step
- [File Change Processing](./decree/file-change-processing) — the file-trigger path in full
- [Routing to Departments](./decree/routing) — handing work to a specific hermes profile
- [Build On It](./build-on-it) — the frozen HTTP contract, if you are integrating from outside
