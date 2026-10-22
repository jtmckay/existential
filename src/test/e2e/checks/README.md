# e2e checks

**An e2e check is a markdown file.** Adding one is adding a file here — the same
move this repo already made for services, cron jobs and migrations. Nothing
enumerates them.

A check has the same shape as a decree migration: YAML frontmatter naming a
machine, then prose explaining what it proves. It is delivered as a decree
**message**, not a migration — `e2e.sh` drops the applicable ones into the
inbox of the daemon whose project has their machine (see [Which daemon runs
it](#which-daemon-runs-it)) **after** the container-health gate and after both
daemons have finished their migrations. The daemon runs them and writes
`runs/<id>/{message.md,events.jsonl,<NNNN>-<state>-<script>.log}` for each, and
`e2e.sh` copies that out to `e2e-out/` and grades it.

Checks are dropped in rather than shipped in `automation-examples/` — that
directory is what a user's quest copies from, and test code has no business in
the product tree.

## Why messages, and why after the migrations

A failed migration blocks every migration after it, so as migrations the first
failing check would hide every later one. The one that actually bit us is
timing: **migrations run as the daemon boots**, so a check written as a
migration judges a stack that is still starting. Run that way, `00-services`
failed hermes, appsmith, lowcoder, nocodb and nextcloud across four quests whose
containers the health gate then found perfectly healthy.

And each decree pass drains the inbox *before* it runs migrations, so a check
dropped too early runs ahead of the setup it verifies. `e2e.sh` waits until
`decree status` shows no migration left to run (or one blocked behind a failed
one) before dropping anything.

## Frontmatter

| Key | Read by | Meaning |
|---|---|---|
| `machine` | decree, `e2e.sh` | the machine to run — a shipped one, or the sibling `.yml` |
| `params` | decree | the machine's declared `data`; decree fails a run that passes anything undeclared |
| `e2e_check` | `results.sh` | this check's name; how a run dir is traced back here |
| `requires` | `e2e.sh` | `EXIST_IS_*` vars that must be true, else the check is not staged |

## Which daemon runs it

There are two, they do not have the same mounts, and a check goes to the one
that can run it. **This is derived from `machine:`, never declared** — whichever
daemon's project has `machines/<machine>.yml`, asking `automation` first, so a
machine both have stays where it has always run:

| | `automation` | `automation-backup` |
|---|---|---|
| owns | everything that reasons, routes, or calls a service API | `triage`, the backups, `notes_pull` |
| has | service credentials, read-write `/secrets`, the inbox the webhook writes to | `/repo` read-only, `/volumes`, the master `.env` |

A check with a sibling machine is staged into `automation`. Each daemon has its
own `inbox/` and `runs/`, and `e2e.sh` drains and grades both.

Getting this wrong is loud now: a message naming a machine its project does not
have is a `failed` run whose events say `invalid_message`.

## The sibling `.yml` and `.sh`

A check with neither reuses a machine the stack already ships. A check with
them gets `<name>.yml` staged as the clone's `automation/machines/<machine>.yml`
and `<name>.sh` as `automation/scripts/<machine>.sh`, so test code never
appears in a user's project. Write the machine as one state that invokes the
script, and the script as any other: `set -euo pipefail`, non-zero to fail.

**It runs inside a decree container** — `automation` unless the section above
says otherwise. That buys `rclone`, `jq`, `yq`, `curl` and `tsx` from the image,
service credentials from its compose environment, a read-write `/secrets`, and
DNS to every container on the `exist` bridge. It buys no Docker socket — anything
needing one belongs on the host in `e2e.sh` — and, in `automation`, **no
`/repo`**: that mount belongs to `automation-backup`, so a script that wants to
read the rendered stack either runs there or has its `.stage.sh` read the file
on the host and leave the answer in `/secrets`.

## The sibling `.stage.sh`

Setup a running container cannot do to itself — anything mounted read-only or
read once at boot, like `lib/` or the webhook's route table — goes in
`<name>.stage.sh`, which `e2e.sh` runs on the host before the stack comes up. It
gets `$WORK` (the clone) and nothing else.

Keep it small. Anything that can wait until the check runs belongs in the
script, where the rendered credentials actually exist — staging happens before
the templates are rendered, so `.stage.sh` has no passwords to work with. The
harness has no business knowing which services a check touches, so nothing
check-specific belongs in `e2e.sh`.

## What a check may assume, and what it must not

decree runs **one message at a time** *per daemon*, and a check IS that message.
Any work a check triggers — a webhook firing, a router matching, a processor
running — is queued *behind* it and cannot start until it returns. A check can
prove work was **enqueued**; it can never wait for it to finish.

So push assertions down to where they can run: a probe processor should validate
its own inputs and exit non-zero. `e2e.sh` waits until both daemons have nothing
queued or running, so that queued work runs — and is graded — inside the same
wait.

## Verdict

decree mirrors each run's final state into its `message.md`. `state: done` is a
pass; `failed`, or no final state at all, is a failure. `results.md` in the
output directory lists one line per run.

**Every run in the clone is graded, not just the checks e2e staged.** The work a
check triggers lands in `runs/` as its own run, and that is where its success or
failure actually shows up — grading only the named checks once let a live run
report PASS while the router was failing on every event it routed. The
product's own migrations are graded on the same terms. Runs without an
`e2e_check` key are named by their machine.

A quest also fails if the daemons never finished their migrations, or if there
were no runs at all: a run that verified nothing must not read green.
