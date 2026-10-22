# Messages

A message is one markdown file: YAML frontmatter (structured) plus a body (the task, free text).
One message is one run. decree reads and writes only the frontmatter and never changes the body.

```markdown
---
machine: feature
params:
  max_rounds: 3
---
# Add rate limiting to /api/upload

## Overview
## Outcome
## Constraints
## Acceptance Criteria
```

## Frontmatter keys

| Key | Who sets it | Meaning |
| --- | --- | --- |
| `machine` | Author, `decree emit`, cron | Machine name (`machines/<name>.yml`). Required: there is no default machine. |
| `params` | Author, `decree emit --param` | Values for the machine's `data` (string, int, number or bool), one of the `enum` values if the entry has one. Unknown names, wrong types and values outside the `enum` fail validation. |
| `id` | decree only | `YYYYMMDDTHHMMSS.ffffffZ-xxxxxx`, UTC to the microsecond, so ids sort in the order messages arrived, a migration's run included. Names the queued file and the run folder. |
| `state` | decree only | Mirror of the run's current state, in `runs/<id>/message.md`. Never set it. |
| `parent`, `depth` | `decree emit`, decree | The run that emitted this message (or invoked this child run), and the chain depth. |
| `trigger` | decree only | `migration`, `cron`, `emit`, `inbox` or `invoke`. |
| `arrived_as` | decree only | The name a file written into `inbox/` had before it got its id. |
| `migration` | decree only | In a migration's `runs/<id>/message.md`: the file it came from (`01-a.md`). |
| `traceparent`, `tracestate` | decree, `decree emit`, any tool | W3C Trace Context: the run joins this trace, under this span. An invalid `traceparent` is ignored and the run starts a new trace. |
| `to`, `event` | `decree event`, any tool | Only in a reply to a waiting run (below). |

Any other key is kept as written and ignored.

## Migrations: ordered, run once

`.decree/migrations/*.md` is the queue for work that must happen exactly once, in order, with its
history in git.

- **Name** them with a numeric prefix padded to the width the project will need:
  `001-add-login.md`, `002-rate-limit-upload.md`. They run in byte order of filename, so `100-`
  sorts before `99-`. Use the next free number. A project that outgrows the width continues with
  a letter prefix (`A01-`, then `B01-`), because letters sort after digits. `decree check` warns
  when a new name sorts before one that already ran.
- **Immutable.** decree never edits, moves or renames a migration; neither do you. A run works on
  a copy in `runs/<id>/message.md`, with a time id like every other run and
  `migration: <file>`. A migration that has a run is never started again. To fix a processed
  migration, write a new one that says what it fixes.
- **Named by its file.** Wherever you name a run (`decree process --retry`, `decree daemon
  --retry`, `decree status <id>`, `decree tail <id>`, `decree event`), the migration's file
  name or stem (`01-a.md`, `01-a`) works too and means its newest run. Status lines, `process`
  notices and the built-in `commit`'s title show the file beside the run id.
- **Ledger.** `.decree/processed.md` (committed) lists one filename per line. When a migration's
  run reaches a final state other than `failed`, decree appends its filename *before* that final
  state's `onentry` scripts run, so `done: { final: true, onentry: [commit] }` commits the code
  and the ledger line together. decree never runs git itself.
- **Strict order.** Migration N+1 starts only when N is processed and `inbox/` is empty, so
  follow-ups that N emits run first. A migration whose run is `failed`, `interrupted` or
  `waiting` blocks every later one, and a failed migration stops `decree process` at once.
  A failed follow-up has left `inbox/`, so it does not hold back the next migration.
- **Validated first.** `decree process` checks every pending migration (frontmatter, machine,
  `params`) before running any, and runs nothing if one is invalid.

### Writing a good migration

- One concern, day-sized: implementable in one agent session and reviewable on its own. Five
  subsystems means five migrations.
- Self-contained: no dependency on a sibling migration's runtime state.
- **Describe the outcome, not the steps.** A message says what is true when it is done and
  why; the agent chooses how. A message that says *how* ties the agent to the implementation
  its author pictured, and when the code differs, the run stops or the agent forces the plan.
  This is declarative configuration, as `infra` declares a desired state and `apply` reaches
  it.
  - **Outcome** (belongs in a message): behaviour a user or another program can observe; the
    public contract (command and flag names, file names, formats and locations, exit codes,
    messages printed); what must not change; why the change is wanted.
  - **Steps** (left out): which functions, modules or files to change, in what order, which
    data structures. Name one only as a constraint ("no new dependencies", "decree itself runs
    no git command"), never as a suggestion.
  - The test for any sentence: if a different correct implementation would fail it, it is a
    step.
- The body has four sections:

  ```markdown
  # <title>

  ## Overview
  Why the change is wanted.

  ## Outcome
  What is true afterwards, as a user or another program sees it.

  ## Constraints
  What must hold or must not change.

  ## Acceptance Criteria
  Given / When / Then, each observable.
  ```

  A message with other headings is still valid and runs the same: decree never reads the
  body.
- One sentence, written as a step and as an outcome:

  > **Step:** The warning has its own rule id, following the existing warnings.
  >
  > **Outcome:** `decree check` shows this warning and still exits 0, in text, JSON and
  > SARIF.

  The step assumed the existing warnings had rule ids; they had none, and the run stopped.
  The outcome holds for any correct implementation.
- Acceptance criteria as Given / When / Then, each automatable:

  ```markdown
  - **Given** <precondition>
    **When** <action>
    **Then** <observable result: exit code, file contents, output, response>
  ```

  Avoid outcomes like "works correctly".

## Inbox: first in, first out

`.decree/inbox/*.md` holds queued messages, run in the order they arrived. Not committed.

- Each is named `<id>.md`. A file written under any other name (`01-hi.md`) gets a fresh id
  the first time `process` or `daemon` sees it, as `decree emit` would have given it, so it runs
  after everything queued before; files first seen together go by modification time, then
  name. Its old name is kept as `arrived_as`, in `runs/<id>/message.md` too.
- `id`, `state`, `trigger`, `arrived_as` and `migration` are decree's alone: a file placed in
  `inbox/` gets decree's own, so a copy of a migration or of a run's `message.md` runs again as
  a new run, never as a run of that migration.
- A failed inbox run does not stop `decree process`: it prints the run with
  `decree process --retry <id>` and goes on with the next file. When the inbox is empty it lists
  every run that failed in the pass and exits 1.
- People may drop a file in directly. Programs write `.<name>.tmp`, then rename it to `<name>.md`;
  files starting with `.` are ignored, so nobody reads a partial file.
- From a script, use `decree emit`, which does the temp-file-and-rename for you, sets `parent`,
  `depth` and `trigger: emit`, and refuses past `max_depth` (10):

  ```bash
  "${DECREE}" emit --machine feature --param max_rounds=3 <<'EOF'
  # Follow-up: split rate limiting per route

  ## Overview
  ## Outcome
  ## Constraints
  ## Acceptance Criteria
  EOF
  ```

- Inside a run, the emitting state must list the target machine in its `emits:`; otherwise
  `decree emit` exits 1. `decree graph` draws these edges in `system.md`.
- Stdin that starts with frontmatter is a whole message: `decree emit` keeps its frontmatter
  (less the keys decree sets), `--machine` and `--param` override it, and `--machine` may be
  left out when it names a machine. Frontmatter that is not valid is refused, as
  `decree check` would, and nothing is queued.

### Run a message again

```bash
decree emit < .decree/migrations/01-a.md
```

or copy the file into `inbox/`. Either way it is a new inbox run with the same frontmatter and
body; the migration file and `processed.md` are untouched.

## Cron

`.decree/cron/*.md` files are message templates that `decree daemon` drops into `inbox/` on a
schedule. The `cron:` key is a standard cron expression; the rest is an ordinary message.

```markdown
---
cron: "0 3 * * *"
machine: develop
---
# No dependency has an advisory that a patched version fixes

## Overview

A vulnerability whose fix is published should not stay in the build overnight.

## Outcome

`cargo audit` reports no advisory that a compatible patched version of the dependency fixes.

## Constraints

- The project's own code does not change, only the versions of its dependencies.

## Acceptance Criteria

- **Given** the project after the run
  **When** `cargo audit` runs
  **Then** it lists no advisory that a compatible patched version fixes
```

`decree status --cron` lists them with their next fire time.

## Replies to a waiting run

A run in a `person` state waits for a reply with a **wait id** (`<run id>.w<seq>`). The
state's `ask` script tells someone the question, the options and how to answer. A reply is an
inbox message with `to:` (the wait id, or the run id meaning "its current wait") and `event:`
(one of the options); the body is an optional note the run's later scripts read through
`DECREE_RECEIVED`.

```bash
decree event 20261001T145120.000000Z-9c2e57.w15 retry -m "plans.toml lives in config/."
```

writes:

```markdown
---
id: 20261001T160301.482113Z-9be210
to: 20261001T145120.000000Z-9c2e57.w15
event: retry
---
plans.toml lives in config/.
```

Any tool (a chat bot, a web UI) can write the same file. A reply to a stale wait id or with an
event that is not an option is not applied; it shows up in `decree status` as a failed message.
