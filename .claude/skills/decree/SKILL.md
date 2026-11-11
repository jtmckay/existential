---
name: decree
description: >
  Work in a decree project: messages (migrations, inbox, cron), machines (YAML statecharts in
  .decree/machines/) and scripts (.decree/scripts/), checked with `decree check`, drawn with
  `decree graph`, and queued with `decree emit`. Prefers the simplest machine: states are added
  only when the user asks or a run shows the need.
  INVOKE when: the user mentions decree or .decree/; writes or edits a migration, inbox message,
  cron file, machine or script; asks how to automate, schedule or chain work, ask a model or a
  person to decide a step, or why a run failed, is waiting or was interrupted.
  SKIP for: shell scripting, CI or infrastructure work unrelated to decree.
---

# decree

decree runs work through three building blocks:

- A **message** (markdown) says *what* to do in its body, and *which machine* does it
  (`machine:` in the frontmatter). Migrations, inbox messages and cron templates are all messages.
- A **machine** (`.decree/machines/<name>.yml`) says *in what order*: a W3C SCXML statechart
  written in YAML. States, what each state invokes, and which event leads to which state. No
  code, no paths.
- A **script** (`.decree/scripts/<name>.sh`, or `.decree/scripts/<machine>/<name>.sh` for one
  machine's own) does one piece of work and reports one outcome: exit 0 is `done`, non-zero is
  `error`, or the script names a richer event in a file (`echo pass > "$DECREE_EVENT_FILE"`).

Every state invokes one function, and its result is an event. The function is a script, a child
machine (`machine: deploy`), or a built-in decision: `check` (deterministic: `true` or `false`),
`model` (a model picks an option, asked through a router machine) or `person` (the run pauses
until a reply picks one). `invoke` has exactly one key, which names the kind. AI and people
appear only where a machine invokes `model` or `person`.

## Rules

- **Start with the simplest machine.** Write the most naive machine that does the job: the
  scripts it needs, one state each, in a straight line (`done` → the next state), ending in
  `done`. `error` already goes to `failed` implicitly; don't write it.
  - Add nothing else until the user asks for it or a run has shown it is needed: no `check`,
    `model` or `person` decisions, loops or round counters, `data` params, `attempts`,
    `timeout`, child machines, `emits`, compound states or one state per case.
  - When an addition is warranted, add the smallest one that solves the problem, and say why
    in the state's comment (`# the local model fails often: try Claude second`).
  - The cheapest fixes come first, in this order: change the script; `attempts`; a transition
    on an event the script names; a `check`; a `model` or `person` decision; a child machine.
  - Asked to design a machine, show the simple version, and list possible additions in prose
    as options, not in the YAML.
  - When `develop` runs show that a failed verify is worth more rounds, decree's
    [escalation ladder](https://github.com/jtmckay/decree/blob/main/docs/escalation.md)
    recipe adds them: rounds with a cheap agent, one with Claude, then a person.
- **Never edit a migration.** Files in `.decree/migrations/` are immutable; the ones listed in
  `.decree/processed.md` have run. To change something, write a new migration with the next
  number.
- **Name migrations so they keep their order.** They run in byte order of filename, so `100-`
  sorts before `99-`: pad the number to the width the project will need (`001-`), and when a
  project outgrows it, continue with a letter prefix (`A01-`, then `B01-`), because letters sort
  after digits. `decree check` warns when a new name sorts before one that already ran.
- **One concern per migration**, day-sized, with Given / When / Then acceptance criteria whose
  outcomes are observable (exit codes, file contents, output).
- **Describe the outcome, not the steps.** A message says what is true when it is done and
  why; the agent chooses how, as `infra` declares a desired state and `apply` reaches it.
  - **Outcome** (belongs in a message): behaviour a user or another program can observe; the
    public contract (command and flag names, file names, formats and locations, exit codes,
    messages printed); what must not change; why the change is wanted.
  - **Steps** (left out): which functions, modules or files to change, in what order, which
    data structures. Name one only as a constraint ("no new dependencies", "decree itself runs
    no git command"), never as a suggestion.
  - The test for any sentence: if a different correct implementation would fail it, it is a
    step.
  - The body: `## Overview` (why), `## Outcome` (what is true afterwards), `## Constraints`
    (what must hold or not change), `## Acceptance Criteria` (Given / When / Then,
    observable). `reference/messages.md` shows a step rewritten as an outcome.
- **Always set `machine:`** in a message. Pick from `.decree/machines/` (`ls .decree/machines`).
- **Before writing a machine, run `decree schema` and read
  `.decree/schema/v1/machine.schema.json`**, the JSON Schema of every machine key, and write
  against it. Read `events.schema.json`, `request.schema.json` and `reply.schema.json` in the
  same folder before writing a router or anything that reads a run.
- **Scripts choose how, machines choose what runs next.** A script may decide *how* to do its
  one job from its params and environment: which workflow file, which model for this attempt,
  which flags. A choice of *which step runs next* is a transition, on `done` or an event the
  script names. Make it a decision state (`check`, `model`, `person`) only when the step after
  it differs, and the choice is worth seeing in the graph, testing with `decree check`, or
  giving to a model or a person.
- **Route with a typed router.** For a `model` decision that routes work (which model, which
  path), point `router:` at a typed router (a classifier such as GLiNER2.5-Decide, or a model
  constrained by `reply_schema`): it cannot answer outside the options and costs little. Keep
  untyped models (`claude -p`) for the work itself. To combine several routers by a quorum, use
  the [consensus recipe](https://github.com/jtmckay/decree/blob/main/docs/routers.md#consensus-of-several-routers)
  (a router machine, no new decision kind).
- **Queue follow-up work with `decree emit`**, never by writing into `.decree/inbox/` by hand
  from a script. The emitting state must list the target in `emits:`.
- **A file a person writes into `.decree/inbox/` runs in the order it arrived**: the first
  `process` or `daemon` to see it gives it a fresh id, renames it `<id>.md` and records its old
  name as `arrived_as`. decree replaces `id`, `state`, `trigger` and `migration` there, so to
  run a message again (a migration, a run's `message.md`), run `decree emit < <file>` or copy
  it into `inbox/`.
- **Name a migration's run by its file.** A migration's run has a time id like every other run;
  `decree status 01-a`, `decree process --retry 01-a.md`, `decree tail 01-a` and `decree event
  01-a <event>` take the migration's file name or stem and mean its newest run.
- **Run `decree check` after every change** to a machine, script, message or cron file, and
  `decree graph` after changing a machine. Commit `.decree/graph/`.
- **Read decree's output as JSON, never by parsing its text**: `decree check --format json`,
  `decree status [<id>] --format json`, and `--format json` on `emit`, `event`, `stop`,
  `prune`, `graph`, `schema`, `skill`, `upgrade` and `process --dry-run` print one JSON document, described by
  `.decree/schema/v1/cli/<command>.schema.json`. Exit codes are the same as in text.
  `decree check --format json` gives each error's `rule`, `file`, `line` or `state` and
  `message`.
- **Scripts must be safe to re-run**, after an interruption or a failure halfway:
  `decree process --retry` runs the step again. Check that the result works (`pip --version`
  runs), not that a file exists.
- **Keep a step's previous output until it has a new one.** A script that rewrites a file
  the next attempt or round reads (`gaps.md`, a report) sets the old one aside and puts it
  back if the attempt dies, so a crashed attempt never leaves the retry with nothing:

  ```bash
  [ ! -f "${out}" ] || mv "${out}" "${out}.last"
  trap '[ -s "${out}" ] || [ ! -f "${out}.last" ] || mv "${out}.last" "${out}"' EXIT
  ai "${prompt}"            # writes ${out}
  rm -f "${out}.last"
  ```

- **Call AI only through `ai`** from `lib/ai.sh`, never `claude` or `opencode` directly: it
  waits out Claude's usage limit, nudges OpenCode back after a rejected write, logs every call
  in `.decree/ai-use.md` and keeps the agent from naming an event. Pick the backend with a
  data entry `ai_cli` (a message's or a parent's `params` set it per run), which wins over
  the project's `AI_CLI`. Every prompt says where scratch files go
  (`$DECREE_RUN_DIR`): OpenCode's `external_directory` permission covers its file tools, not
  its shell, so it is no sandbox.
- **Declare the environment.** A command, package or tool the project needs is a line in
  `.decree/lib/infra/requirements`, added by a message for the `infra` machine, never
  installed by another machine's step. Nothing runs `sudo`: a step only a person can do prints
  the exact command and fails, and the person runs it, then `decree process --retry`.
- **Check a boundary with a script, not only a prompt.** When an agent must not change
  something (QA never edits app code), a script after it checks, and fails the step if it did.
- **Shared code, config and data go in `.decree/lib/`** (`$DECREE_LIB`); `scripts/` holds only
  what states invoke. Variables and secrets go in `.decree/.env` (every script) or a machine's
  `env_file: .env.<name>` (that machine's scripts only); both are gitignored, and
  `.decree/.env.example` is the committed template.
- **What a machine keeps between runs goes in `$DECREE_STORE`** (`.decree/store/<machine>/`)
  and is declared under the machine's `store:`, with what it is and which states read or write
  it. A run's own files go in `$DECREE_RUN_DIR`; shared code and config in `$DECREE_LIB`;
  project-wide files no machine owns (a test tool's browsers) in `.decree/cache/`. Never
  `tee` decree's output: `process` and `daemon` keep it in `.decree/process.log`.
- **A step that waits for a shared resource is an invoked state with a `timeout`** (ComfyUI's
  queue, a model unloading), not an `onentry` script, which has none. Keep `onentry` for quick
  steps.
- **What needs a person is in `.decree/attention/`.** Read it first when a run is failed,
  waiting or stuck, and do what each file says: `decree event <wait id> <option>` for a wait,
  `decree process --retry <id>` for a failed or interrupted run. Never edit an attention file
  to answer; never write one from a machine's script. A step whose failure must stop every
  run writes `$DECREE_RUN_DIR/hold` (what `keep` does), and decree turns it into a holding
  attention file. Any `.md` file a person or another tool puts in the folder halts the queue
  until it is deleted. To pause the queue, `decree stop`: the runs going now finish, and
  nothing more runs until `.decree/attention/manual-stop.md` is deleted; Ctrl-C interrupts the
  run instead.
- **Never delete run folders to clean up**; they are the record. Use
  `decree prune --older-than <age>`.
- Do not commit `.decree/inbox/`, `.decree/runs/`, `.decree/store/` or `.decree/cache/`.

## Commands

| Command | Use |
| --- | --- |
| `decree check [--format json\|sarif]` | Validate every machine, script name, pending migration, inbox message and cron file. Exit 1 lists one error per line (`json`: one document; `sarif`: a SARIF 2.1.0 log for code scanning). |
| `decree graph` | Write `.decree/graph/<machine>.md` (Mermaid) for every machine, plus `system.md`. |
| `decree schema` | Write a local copy of the JSON Schemas of machines, messages, events and router files to `.decree/schema/v1/` (ignored by git). |
| `decree skill [--ai claude\|copilot]` | Refresh this skill after upgrading decree; other files in the skill folder are kept. |
| `decree` | Print a synopsis of the quick start and run nothing; run the queue with `decree process`. |
| `decree upgrade [--format json]` | Print how to upgrade decree (the install line, pinned with `\| sh -s -- <tag>`, and `cargo install --git … --force` for a cargo copy) and what to run in each project after. It runs nothing: a person runs the line. |
| `decree emit [--machine <m>] [--param k=v]...` | Queue a message from stdin: a body for machine `m`, or a whole message whose frontmatter the flags override (`decree emit < <file>` runs a message again). Prints the new id. |
| `decree process [--dry-run] [--quiet] [--machine <m> \| --exclude-machine <m>]` | Run everything queued: replies, pending runs, the inbox (FIFO), then migrations in order, printing each run's output. `--quiet` for cron and CI. `--machine` runs only those machines, `--exclude-machine` all but those (repeatable, comma-separated; or `DECREE_MACHINES`, `DECREE_EXCLUDE_MACHINES`), so several processes can share one folder. |
| `decree process --retry [<id>] [--state <s>]` | Continue a failed or interrupted run first: `<id>` (or a migration's file name or stem, meaning its newest run), or the migration blocking the queue. The failure message prints the exact command. |
| `decree daemon [--interval <duration>] [--retry [<id>]] [--machine <m> \| --exclude-machine <m>]` | The same, in a loop, with cron, every `2s` by default; `--machine` and `--exclude-machine` as for `process`. |
| `decree status [<id>] [--cron] [--all] [--format json]` | Starts with `Attention:` (the files in `.decree/attention/`, those that hold first), then what blocks the queue and the command that continues it, runs by status (`--all`: every run), and active runs in projects below; one run's events; cron schedule (text only). |
| `decree tail [<id>]` | Follow each run's output as it comes, or one run's until it stops. |
| `decree event <wait id> <event> [-m <note>]` | Answer a run waiting in a `person` state; a run id or a migration's name means its current wait. |
| `decree stop [-m <note>]` | Let the runs going now finish, then hold the queue until `.decree/attention/manual-stop.md` is deleted (no restart needed). Ctrl-C interrupts the run instead. |
| `decree prune --older-than <age> [--dry-run]` | Delete finished run folders older than `30d`, `12h`, `90m`, `90s`; keeps failed migrations and children of unfinished runs. |

`process` exits once nothing more can run, leaving `person` waits and `timeout`s for the next
`process`; `daemon` keeps polling, fires cron and continues runs as replies arrive, so unattended
work runs under `daemon`. Both read machines and `.env` files again before each run: an edit
applies to the next run without a restart, and an edit that fails `decree check` is not used
until fixed (the old machines keep running and the errors are printed).

## The built-in machines

`decree init` writes three working machines besides the router. Start from them before writing
a machine of the same kind. Each starts with `clean_tree` (a root `onentry`: it fails the run
unless the git work tree is clean, naming each `interrupted` or `failed` run that may have left
the changes, with its `--retry` and `git stash push` commands, also in its attention file) and
ends with `commit` (`done`'s `onentry`: the run's work as one commit, titled with the message's
first heading, and the file for a migration's run), or, in `failed`, with `keep` (the
run's changes stay in the work tree, and `keep` writes the run's `hold`, so its attention file
in `.decree/attention/` holds every run until the run is retried). All three touch only the
project folder. Before queuing work for them, commit or stash any changes. To continue: answer
any `STOP` in `plan.md`, delete `STOP`, `decree process --retry <id>`, which builds on the
kept changes and removes the hold. To drop the run: stash its changes and delete its
attention file. Never run `develop`, `infra` or `qa` in two processes in one checkout (they
share the work tree through `clean_tree` and `commit`); give each its own git worktree. For divergent work,
or to keep editing while runs go on, suggest a
git worktree the user makes and runs decree in (`git worktree add ../app-exp -b exp`, then
`decree process` there): each checkout has its own runs and inbox, and its branch its own
`processed.md`. A new worktree has committed files only: copy `.decree/.env` in and run
`.decree/lib/infra/run.sh apply` there first.

`develop`: `precheck` →
`implement` → `gate` → `verify`, with `fix` and `final_gate` only when the gate fails. Its scripts
source `lib/ai.sh` (`ai`, which calls `ai_<backend>`: a data entry `ai_cli`, else
`AI_CLI`, else the `--ai` init chose) and
follow the run-directory files in `reference/scripts.md` (`progress.md`, `STOP`, `gate.log`,
`plan.md`): a person answers a `STOP` in `plan.md`, deletes `STOP` and
retries. `precheck` runs
`lib/infra/run.sh check`. The project fills in `scripts/develop/gate.sh` with its own checks; until then it
runs nothing, says so and names `pass`. The gate names `pass` (to `verify`) or `fail` (to `fix`,
then `final_gate`, whose `fail` ends the run); a non-zero exit means the checks could not run,
such as a missing tool, and goes to `failed` without `fix`. `lib/ai.sh` runs the agent with
`DECREE_EVENT_FILE=/dev/null` and empties the caller's event file after it, so a gate the agent
runs names no event for its caller. `verify`
ends in `pass` or `fail` from the AI's `VERDICT:` line.

`infra`: `declare` → `apply`. The AI edits `lib/infra/requirements` (`kind name version
source`, one resource per line, in dependency order), adding a kind in `lib/infra/kinds/` only
when none fits; `apply` runs `lib/infra/run.sh apply`, which installs what is missing and checks
every line. The first `infra` migration builds the environment; later ones add to it.

`qa`: `recon` → `attack` → `run` → `triage` → `report`. The AI writes chaos tests in
`QA_DIR` (`tests/chaos`) against `lib/qa/invariants.md`, each naming a wrench from
`lib/qa/wrenches.md`; triage marks each real bug's tests with the framework's strict
expected-failure marker and writes one report per root cause (the broken invariant and the
expected behaviour, no fix), and `report` emits each as a `develop` message. A guard (`lib/qa/qa.sh`) fails any step whose AI changed a file outside
`QA_DIR`. It does not start until `QA_RUN` in `lib/qa/qa.sh` names the suite's command; once
qa finds bugs, the gate should run it too.

## Worked example

A migration for the `feature` machine:

```markdown
---
machine: feature
---
# Rate-limit /api/upload

## Overview

One API key can flood uploads and slow the service for every other key.

## Outcome

Each API key makes at most 10 uploads per minute on `POST /api/upload`.

## Constraints

- Other endpoints respond as before.

## Acceptance Criteria

- **Given** a key that has uploaded 10 times in the last minute
  **When** it uploads again
  **Then** the response is 429 with `Retry-After`
```

The smallest machine:

```yaml
# Graph: ../graph/hello.md
name: hello
description: Run one script.
initial: greet
states:
  greet:
    invoke: greet                  # runs scripts/greet (or scripts/hello/greet)
    transitions: { done: done }    # exit 0 -> done; non-zero -> failed, implicitly
  done:   { final: true }
  failed: { final: true }          # every machine has one
```

A machine grows one reason at a time. First, the straight line that does the job:

```yaml
# Graph: ../graph/develop.md
name: develop
description: Implement a message, then test it.
initial: implement
states:
  implement:                       # the job needs two scripts: one state each, in a line
    invoke: implement
    transitions: { done: test }
  test:
    invoke: test
    transitions: { done: done }
  done:   { final: true }
  failed: { final: true }
```

Real runs then fail at random in `implement`, and a re-run passes: the cheapest fix is
`attempts: 3` on its invoke. Later the local model often fails where Claude would not: give
each attempt a value instead of adding a state, and say why.

```yaml
  implement:
    invoke:                        # the local model fails often: try Claude third
      script: { name: implement, attempts: [local, local, claude] }
    transitions: { done: test }
```

The script picks the model from the attempt, a choice of *how*, not of what runs next.
`attempts` retries after `error` only; to have a stronger model answer a weaker one's `STOP`,
transition to a child machine.

```sh
case "$DECREE_ATTEMPT_VALUE" in
  claude) claude -p "$(cat "$DECREE_MESSAGE")" ;;
  *)      ollama run qwen3:8b "$(cat "$DECREE_MESSAGE")" ;;
esac
```

## Reference files

Read the one you need; don't load them all upfront:

- **`reference/messages.md`**: frontmatter keys, migrations and `processed.md`, the inbox,
  cron files, `decree emit`, replies to a waiting run.
- **`reference/machines.md`**: the graph line, every machine key, the invoke types, conditions, choices and
  routers, composition, events and transitions, validation rules, full examples.
- **`reference/scripts.md`**: where scripts live, how they run, how they report an event,
  every `DECREE_*` variable.
- **`reference/runs.md`**: run folders, `events.jsonl`, run status, waiting and interrupted
  runs, `decree process --retry`, graphs.

The reference files sit next to this file, in `reference/`.
