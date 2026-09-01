# e2e checks

**An e2e check is a markdown file.** Adding one is adding a file here — the same
move this repo already made for services, cron jobs and migrations. Nothing
enumerates them.

A check is a [decree message](../../../.claude/skills/decree/): YAML frontmatter
naming a routine, then prose explaining what it proves. `e2e.sh` drops the
applicable ones into the clone's inbox after the stack is up; the daemon runs
each independently and writes `runs/<id>/{message.md,routine.log,run.json}`;
`e2e.sh` copies that out to `e2e-out/` and grades it.

## Why messages and not migrations

Migrations look like the right fit — one file, ordered, run once — but
`decree process` returns the moment a message dead-letters, so the first
failure hides every later result. That is correct for migrations, where step 12
may depend on step 11, and wrong for tests, where the whole point is to learn
everything that is broken in one run. `decree daemon` keeps draining the inbox
past a dead letter, so a message gets the ordering and the per-run record
without the halt.

## Frontmatter

| Key | Read by | Meaning |
|---|---|---|
| `routine` | decree | the routine to run — a shipped one, or the sibling `.sh` |
| `e2e_check` | `results.sh` | this check's name; how a run dir is traced back here |
| `requires` | `e2e.sh` | `EXIST_IS_*` vars that must be true, else the check is skipped |
| `needs_routines` | `e2e.sh` | decree routines to enable in the clone's `config.yml` |

Every other key becomes an environment variable for the routine — that is
decree's own contract, and it is how `00-services.md` configures `triage`.

## The sibling `.sh`

A check with no `.sh` reuses a routine the stack already ships. A check with one
gets it staged into the clone's `automations/shared_routines/` and registered,
so test code never appears in a user's `config.yml`. Write it as an ordinary
routine (`.claude/skills/decree/reference/routines.md`): `DECREE_PRE_CHECK`
block, `set -euo pipefail`, non-zero to fail.

**It runs inside the `decree` daemon.** That buys `mc`, `rclone`, `jq`, `yq`,
`curl` and `tsx` from the image, service credentials from its compose
environment, the rendered clone read-only at `/repo`, and DNS to every container
on the `exist` bridge. It buys no Docker socket — anything needing one belongs
on the host in `e2e.sh`.

## The sibling `.stage.sh`

Setup a running container cannot do to itself — config that is read once at boot,
like decree's routine whitelist or the webhook's route table — goes in
`<name>.stage.sh`, which `e2e.sh` runs on the host before the stack comes up. It
gets `$WORK` (the clone) and nothing else.

Keep it small. Anything that can wait until the check runs belongs in the
routine, where the rendered credentials actually exist — staging happens before
the templates are rendered, so `.stage.sh` has no passwords to work with. The
harness has no business knowing which services a check touches, so nothing
check-specific belongs in `e2e.sh`.

## What a check may assume, and what it must not

decree runs **one message at a time**, and a check IS that message. Any work a
check triggers — a webhook firing, a router matching, a processor running — is
queued *behind* it and cannot start until it returns. A check can prove work was
**enqueued**; it can never wait for it to finish.

So push assertions down to where they can run: a probe processor should validate
its own inputs and exit non-zero, and `e2e.sh` fails any quest whose inbox has
not drained or whose `dead/` is not empty. Between them, a break anywhere in a
chain is caught, and no check has to poll for another's work.

## Verdict

`run.json` with `exit_code: 0` is a pass. No `run.json`, a non-zero code, or a
dead-lettered message is a failure. `results.md` in the output directory lists
one line per run.

**Every run in the clone is graded, not just the messages e2e dropped.** The work
a check triggers lands in `runs/` as its own run, and that is where its success
or failure actually shows up — grading only the named checks once let a live run
report PASS while `minio-router` was failing on every event it routed. The
daemon's own crons fire too (triage, and the notify it queues); under e2e the
stack lives for a single run, so none of them has any business failing either.
Runs without an `e2e_check` key are named by their routine.

A quest also fails if the inbox never drained, or if there were no runs at all —
a run that verified nothing must not read green.
