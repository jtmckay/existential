# e2e checks

**An e2e check is a markdown file.** Adding one is adding a file here — the same
move this repo already made for services, cron jobs and migrations. Nothing
enumerates them.

A check *is* a [decree migration](../../../../.claude/skills/decree/reference/migrations.md):
YAML frontmatter naming a routine, then prose explaining what it proves.
`e2e.sh` copies the applicable ones into the clone's
`services/decree/decree/migrations/` **before the stack comes up**; decree
applies them during its boot, alongside the product's own migrations, and writes
`runs/<id>/{message.md,routine.log,run.json}` for each; `e2e.sh` copies that out
to `e2e-out/` and grades it.

Checks are copied in rather than shipped in `migrations.example/` — that
directory is what a user's quest copies from, and test code has no business in
the product tree.

## Why migrations, and why the number matters

`decree process` returns the moment a message dead-letters, so a failure early
in the pass hides every later result. That is correct for migrations, where step
12 may depend on step 11, and it used to be the reason checks were inbox
messages instead.

**Number checks above the product's own migrations and the objection goes
away.** The stack's migrations are `10-`–`22-` (ollama models, MinIO buckets);
checks start at `90-`, so every product migration has already run and been
graded before the first check executes. A check that dead-letters halts only the
checks behind it — and with one check, nothing. What that buys in exchange is
one mechanism instead of two: no inbox drop, no drain poll, no dead-letter
dance, and a check that is exercised by the same code path the product uses.

If checks ever grow to the point where one blocking the next is a real loss,
the answer is still a number — give the expensive ones the higher ones — not a
second runner.

## Frontmatter

| Key | Read by | Meaning |
|---|---|---|
| `routine` | decree | the routine to run — a shipped one, or the sibling `.sh` |
| `e2e_check` | `results.sh` | this check's name; how a run dir is traced back here |
| `requires` | `e2e.sh` | `EXIST_IS_*` vars that must be true, else the check is not staged |
| `needs_routines` | `e2e.sh` | decree routines to enable in the clone's `config.yml` |

Every other key becomes an environment variable for the routine — that is
decree's own contract — it is how a check passes configuration to its routine.

## The sibling `.sh`

A check with no `.sh` reuses a routine the stack already ships. A check with one
gets it staged into the clone's `automations/shared_routines/` and registered,
so test code never appears in a user's `config.yml`. Write it as an ordinary
routine (`.claude/skills/decree/reference/routines.md`): `DECREE_PRE_CHECK`
block, `set -euo pipefail`, non-zero to fail.

**It runs inside the `decree` container.** That buys `mc`, `rclone`, `jq`, `yq`,
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
its own inputs and exit non-zero. `decree process` drains the whole inbox before
the daemon starts, so that queued work runs — and is graded — inside the same
wait.

## Verdict

`run.json` with `exit_code: 0` is a pass. No `run.json`, a non-zero code, or a
dead-lettered message is a failure. `results.md` in the output directory lists
one line per run.

**Every run in the clone is graded, not just the checks e2e staged.** The work a
check triggers lands in `runs/` as its own run, and that is where its success or
failure actually shows up — grading only the named checks once let a live run
report PASS while `minio-router` was failing on every event it routed. The
product's own migrations are graded on the same terms, which is the point of
sharing their mechanism. Runs without an `e2e_check` key are named by their
routine.

A quest also fails if decree never reached its daemon phase — meaning it never
finished migrating — or if there were no runs at all: a run that verified
nothing must not read green.
