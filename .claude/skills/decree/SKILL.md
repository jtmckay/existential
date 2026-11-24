---
name: decree
description: >
  Work in a decree project: messages (inbox, cron, order files), machines (YAML statecharts in
  .decree/machines/<name>/machine.yml) and their scripts, checked with `decree check`, drawn with
  `decree graph`, and queued with `decree emit`. Prefers the simplest machine: states are added
  only when the user asks or a run shows the need.
  INVOKE when: the user mentions decree or .decree/; writes or edits an order file, inbox message,
  cron file, machine or script; asks how to automate, schedule or chain work, ask a model or a
  person to decide a step, or why a run failed, is waiting or was interrupted.
  SKIP for: shell scripting, CI or infrastructure work unrelated to decree.
---

# decree

decree runs work through three building blocks:

- A **message** (markdown) says *what* to do in its body, and *which machine* does it
  (`machine:` in the frontmatter). Migrations, inbox messages and cron templates are all messages.
- A **machine** (`.decree/machines/<name>/machine.yml`) says *in what order*: a W3C SCXML statechart
  written in YAML. States, what each state invokes, and which event leads to which state. No
  code, no paths.
- A **script** (`.decree/machines/<machine>/scripts/<name>.sh`, in the folder of the machine
  that runs it) does one piece of work and reports one outcome: exit 0 is `done`, non-zero is
  `error`, or the script names a richer event in a file (`echo pass > "$DECREE_EVENT_FILE"`).

Every state invokes one function, and its result is an event. The function is a script, a child
machine (`machine: deploy`), or a built-in decision: `check` (deterministic: `true` or `false`),
`model` (a model picks an option, asked through a router machine) or `reply` (the run pauses
until a reply, from a person or a program, picks one). `invoke` has exactly one key, which names
the kind. AI and people appear only where a machine invokes `model` or `reply`.

## Starting a project

```bash
decree init                  # .decree/ with decree_ai, decree_order, decree_prune and decree_skill
decree list                  # this project's plugins, then the official ones it can add
decree install decree_develop_rust   # it, decree_develop (its base) and what that needs, installed
```

`init` never prompts and installs no plugin. Add only what the project needs; each plugin's
file (`.decree/plugins/<name>.md`) says what it does, what it needs and how to use it.
For a Rust, Node or React project, add the `decree_develop` variant that fits:
`decree install decree_develop_rust` (or `decree_develop_node`, `decree_develop_react`). Each
extends `decree_develop` with a gate that already runs the ecosystem's standard checks,
conventions its prompts follow, and its tools in its `requirements`; a project with two parts
(a Rust API, a React front end) adds two and names one in each message. A project in another
ecosystem writes its own plugin that extends `decree_develop` with its gate.

## Rules

- **Start with the simplest machine.** Write the most naive machine that does the job: the
  scripts it needs, one state each, in a straight line (`done` → the next state), ending in
  `done`. `error` already goes to `failed` implicitly; don't write it.
  - Add nothing else until the user asks for it or a run has shown it is needed: no `check`,
    `model` or `reply` decisions, loops or round counters, `data` params, `attempts`,
    `timeout`, child machines, `emits`, compound states or one state per case.
  - When an addition is warranted, add the smallest one that solves the problem, and say why
    in the state's comment (`# the local model fails often: try Claude second`).
  - The cheapest fixes come first, in this order: change the script; `attempts`; a transition
    on an event the script names; a `check`; a `model` or `reply` decision; a child machine.
  - Asked to design a machine, show the simple version, and list possible additions in prose
    as options, not in the YAML.
  - When `decree_develop` runs show that a failed verify is worth more rounds, decree's
    [escalation ladder](https://github.com/jtmckay/decree/blob/main/docs/escalation.md)
    recipe adds them: rounds with a cheap agent, one with Claude, then a person.
- **Ordered work is an order file**, `.decree/machines/<machine>/order/*.md`: the official
  `decree_order` plugin runs them at each daemon start (`decree daemon`, `decree daemon --once`), one at
  a time in byte order of filename, each only once `.decree/inbox/` is empty, and records each in
  that machine's `state/order.git.txt` with its hash. An order file says how things should be:
  editing it runs it again, so write it to be safe to re-run. A failed one stops the files after
  it until it passes.
- **Name order files so they keep their order.** `100-` sorts before `99-`: pad the number to
  the width the project will need (`001-`), and when a project outgrows it, continue with a
  letter prefix (`A01-`, then `B01-`), because letters sort after digits.
- **One concern per message**, day-sized, with Given / When / Then acceptance criteria whose
  outcomes are observable (exit codes, file contents, output).
- **Describe the outcome, not the steps.** A message says what is true when it is done and
  why; the agent chooses how, as `decree_infra` declares a desired state and `apply` reaches it.
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
- **Before writing a machine, read
  `.decree/schema/v1/machine.schema.json`** (`decree install` writes it), the JSON Schema of every machine key, and write
  against it. Read `events.schema.json`, `request.schema.json` and `reply.schema.json` in the
  same folder before writing a router or anything that reads a run.
- **Scripts choose how, machines choose what runs next.** A script may decide *how* to do its
  one job from its params and environment: which workflow file, which model for this attempt,
  which flags. A choice of *which step runs next* is a transition, on `done` or an event the
  script names. Make it a decision state (`check`, `model`, `reply`) only when the step after
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
  `daemon` to see it gives it a fresh id, renames it `<id>.md` and records its old
  name as `arrived_as`. decree replaces `id`, `state` and `trigger` there, so to run a message
  again (an order file, a run's `message.md`), run `decree emit < <file>` or copy it into
  `inbox/`.
- **Run `decree check` after every change** to a machine, script, message or cron file, and
  `decree graph` after changing a machine. Commit each `machines/<name>/graph.md` and
  `.decree/system.md`.
- **Read decree's output as JSON, never by parsing its text**: `decree check --format json`,
  `decree status [<id>] --format json`, and `--format json` on `emit`, `reply`, `retry`,
  `cancel`, `pause`, `resume`, `graph`, `upgrade`, `install`, `list` and `export` print one
  JSON document, described by
  `.decree/schema/v1/cli/<command>.schema.json`. Exit codes are the same as in text.
  `decree check --format json` gives each error's `rule`, `file`, `line` or `state` and
  `message`.
- **Scripts must be safe to re-run**, after an interruption or a failure halfway:
  `decree retry` runs the step again. Check that the result works (`pip --version`
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

- **Call AI only through `ai`** from `ai.sh`, never `claude` or `opencode` directly: it
  waits out Claude's usage limit, nudges OpenCode back after a rejected write, logs every call
  in `.decree/ai-use.md` and keeps the agent from naming an event. Pick the backend with a
  data entry `ai_cli` (a message's or a parent's `params` set it per run), which wins over
  the project's `AI_CLI`. Every prompt says where scratch files go
  (`$DECREE_RUN_DIR`): OpenCode's `external_directory` permission covers its file tools, not
  its shell, so it is no sandbox.
- **Declare the environment.** A command, package or tool the project needs is a line in
  the `scripts/requirements` of the project's plugin that extends `decree_infra` (`app_infra`), added by a message for that machine, never
  installed by another machine's step. Nothing runs `sudo`: a step only a person can do prints
  the exact command and fails, and the person runs it, then `decree retry`.
- **Check a boundary with a script, not only a prompt.** When an agent must not change
  something (QA never edits app code), a script after it checks, and fails the step if it did.
- **A machine's helpers, config and data go in `machines/<machine>/scripts/`**, beside the scripts its
  states invoke (`ai.sh`, a prompt template, a workflow file); decree runs only what a state
  names, and scripts reach the rest by path from the project root. Variables and secrets go in `.decree/.env` (every script) or a machine's
  `env_file: .env.<name>` (that machine's scripts only); both are gitignored, and
  `.decree/.env.example` is the committed template.
- **What a machine keeps between runs goes in `$DECREE_STATE_DIR`** (`.decree/machines/<machine>/state/`)
  and is declared under the machine's `state_files:`, with what it is and which states read or write
  it. **Data in `state/`, code in `scripts/`, never code in `state/`**: nothing in `state/` is
  run, sourced or `eval`ed, and settings that choose what runs (rules, a gate, a list of folders)
  are scripts; `decree check` warns about an executable file or `#!` in `state/` and a script
  that runs or sources a path there. A run's own files go in `$DECREE_RUN_DIR`; helpers, config and data in `machines/<machine>/scripts/`;
  project-wide files no machine owns (a test tool's browsers) in `.decree/cache/`. Never
  `tee` decree's output: `daemon` keep it in `.decree/process.log`.
- **A step that waits for a shared resource is an invoked state with a `timeout`** (ComfyUI's
  queue, a model unloading), not an `onentry` script, which has none. Keep `onentry` for quick
  steps.
- **What needs a person is in `.decree/attention/`.** Read it first when a run is failed,
  waiting or stuck, and do what each file says: `decree reply <wait id> <option>` for a wait,
  `decree retry <id>` for a failed or interrupted run. Never edit an attention file
  to answer; never write one from a machine's script. A step whose failure must stop every
  run writes `$DECREE_RUN_DIR/hold` (what `keep` does), and decree turns it into a holding
  attention file. Any `.md` file a person or another tool puts in the folder halts the queue
  until it is deleted. To pause the queue, `decree pause`: the runs going now finish their
  step, and nothing more runs until `decree resume`; Ctrl-C interrupts the runs instead.
- **Plugins are the source.** Each `.decree/plugins/<name>.md` holds one machine folder,
  `.decree/machines/<name>/`: its `machine.yml` (or none: a library of scripts), `scripts/`,
  `cron/`, and seeds for its `state/` and `order/`; `x-` keys are for other tools. decree
  installs plugins only when asked: `decree install` (after a clone, a pull or an upgrade;
  `check` and `daemon` say when one is due); the daemon never installs. To
  keep a deployed project installed, start it with `decree install && decree daemon`
  (or run `decree install` from a git `post-merge` hook); suggest that, not a machine. Edit the installed copy
  (`machine.yml`, `scripts/`, `cron/`), run it, then keep the edit with
  `decree export <name>`, or let the next run's `commit` export it, and commit the
  plugin file. A machine written by hand in `machines/<name>/` is not committed until it is exported
  (`decree check` warns about it). A project's settings for a plugin (`gate.sh`,
  `requirements`, `QA_RUN`, decree_lease's resources) are such edits: they live in its plugin file. Export an edit
  before the next `decree install`: an install never stops over one, it archives the edited
  copy as a plugin file, `.decree/archive/<name>/<time>.md`, and installs the plugin over
  it (`decree check` warns while one is pending). `decree install` that file restores it.
  Cron files are the exception: installed with the plugin the first time, they are then the
  project's, and an install keeps them; `decree install --cron <name>` takes the plugin's.
  An official plugin decree copied in because another extends or needs it (`added <file>,
  needed by <names>`) goes with the last plugin that needed it: after deleting a plugin,
  `decree install` removes each such one nothing in `plugins/` needs any more (`removed
  <file>, no longer needed`; its `state/` and `order/` stay; until then `check` and
  `daemon` warn `added for a need, and nothing needs it now`). `decree install <name>` of one
  keeps it for good; a plugin a person wrote or installed by name is never removed this way.
  `decree list` shows `(needed by <names>)`. Never edit `.decree/cache/plugins/`.
- **Official plugins are `decree_*`, and never edited.** Only an official plugin's name starts
  with `decree_`; never name a project's plugin `decree_*` (P1). Never edit an official
  plugin's file or its installed copy (`decree check` fails with P3; `decree install` restores
  it, archiving the edit), and never `decree export` one. To change what one does, write a
  plugin of the project's own that extends it, holding only the files it adds or replaces:
  `name: app_develop`, `extends: decree_develop`, `scripts: {gate.sh: ...}`. It is installed in
  full as `machines/app_develop/`, its base beside it; send messages to it. It carries its
  base's cron files, so a schedule runs once. A need is met by another plugin with a map:
  `needs: [{decree_infra: app_infra}]`; scripts reach a need through `DECREE_NEED_<NEED>` and
  their own files through `DECREE_MACHINE`. A plugin published at a URL has `source:
  https://...`; `decree install --update` fetches it, shows the diff and asks a person `y/N`
  (an agent never answers it), and `curl -fsSL <url> | decree install -` adds one first.
- **Never delete run folders to clean up**; they are the record. The official `decree_prune` plugin
  deletes finished ones older than `PRUNE_OLDER_THAN` (30d) each week.
- Commit `.decree/plugins/`, `.decree/system.md` and each `machines/<name>/graph.md` and
  `order/`; git ignores the rest of `.decree/machines/`, which `decree install` installs
  from `plugins/`, except any `*.git.*` file (`order.git.txt`) in a machine's `state/`. Do not commit
  `.decree/inbox/`, `.decree/runs/` or `.decree/cache/`.

## Commands

| Command | Use |
| --- | --- |
| `decree check [--format json\|sarif]` | Validate every machine, script name, inbox message and cron file. Exit 1 lists one error per line (`json`: one document; `sarif`: a SARIF 2.1.0 log for code scanning). |
| `decree install [--cron]` | Install every plugin in `.decree/plugins/` as its file says: the step after a clone, a pull or an upgrade. Makes every official plugin (`decree_*`) this decree's copy, printing what changes; archives an installed copy edited in place first. Removes each plugin decree added for a need that nothing in `plugins/` needs any more (`removed <file>, no longer needed`). A plugin already installed keeps its cron files (edited or deleted) unless `--cron`. |
| `decree install <name>... [--cron]` | Install these plugins, archiving an edited installed copy; an official plugin not in `.decree/plugins/` is copied there first, with those it extends or needs, which go when nothing needs them. A name already added for a need is kept from then on. |
| `decree install --update [<name>...]` | Fetch each plugin with a `source` from its https URL, print the diff and ask `y/N` on a terminal; only `y` takes it. |
| `decree install <file\|->`, or `curl -fsSL <url> \| decree install -` | Check a plugin file, copy it to `.decree/plugins/` and install it. |
| `decree list` / `decree export [<name>]` | List the project's plugins (`official` or `own`, `extends <base>`, `differs`, `not installed`, `edited`), the machines no plugin installed, and the official plugins it can add. Write `.decree/plugins/<name>.md` from the installed `machines/<name>/` (its `machine.yml`, `scripts/` and `cron/`; for a plugin that extends another, only what differs from its base); with no name, every plugin of the project's own whose installed copy was edited. Never an official plugin. |
| `decree graph` | Write `.decree/machines/<machine>/graph.md` (Mermaid) for every machine, plus `.decree/system.md`. |
| `decree install` after an upgrade | Takes the new decree's copy of every official plugin, `decree_skill` included; the next daemon start rewrites this skill, keeping other files in the skill folder. |
| `decree` | Print a synopsis of the quick start and run nothing; run the queue with `decree daemon --once`. |
| `decree upgrade [--yes] [--format json]` | Print how to upgrade decree (the install line, pinned with `\| sh -s -- <tag>`, and `cargo install --git … --force` for a cargo copy) and what to run in each project after, then ask y/N before running the install line, and then before running `decree install` in this project; `--yes` runs both without asking. After an upgrade, run `decree install` in each project: it writes the new schemas and installs the plugins. An agent never answers `y` for a person. |
| `decree emit [--machine <m>] [--param k=v]...` | Queue a message from stdin: a body for machine `m`, or a whole message whose frontmatter the flags override (`decree emit < <file>` runs a message again). Prints the new id. |
| `decree daemon --once [--quiet] [--machine <m> \| --exclude-machine <m>]` | Start (firing `@reboot` cron files, so `decree_order` runs the order files), run everything queued: replies, pending runs, the inbox (FIFO), printing each run's output, then exit. `--quiet` for cron and CI. `--machine` runs only those machines, `--exclude-machine` all but those (repeatable, comma-separated; or `DECREE_MACHINES`, `DECREE_EXCLUDE_MACHINES`), so several processes can share one folder. |
| `decree retry <id> [--state <s>]` | Make a failed or interrupted run pending again; a running `decree daemon`, or the next `decree daemon --once`, continues it. The failure message prints the exact command. |
| `decree daemon [--interval <duration>] [--machine <m> \| --exclude-machine <m>]` | The same, in a loop, with scheduled cron, every `2s` by default; `--machine` and `--exclude-machine` as for `--once`. |
| `decree status [<id>] [--cron] [--all] [--format json]` | Starts with `Attention:` (the files in `.decree/attention/`, those that hold first), then runs by status (`--all`: every run), and active runs in projects below; one run's events; `--cron`: cron files and when each fires next (`daemon start` for `@reboot`). |
| `decree tail [<id>]` | Follow each run's output as it comes, or one run's until it stops. |
| `decree reply <wait id> <event> [-m <note>]` | Answer a run waiting in a `reply` state; a run id means its current wait. |
| `decree cancel <id> [-m <note>]` | End a waiting, pending or interrupted run, and the child runs below it, in `failed`; no script runs, and no attention file stays. `decree retry` continues it. |
| `decree pause [-m <note>]` | Let the runs going now finish their step, then run nothing more until `decree resume` (no restart needed). Ctrl-C interrupts the runs instead. |
| `decree resume` | Go on after `decree pause`. |

`daemon --once` exits once nothing more can run, leaving `reply` waits for the next start;
`daemon` keeps polling, fires scheduled cron and continues runs as replies arrive, so unattended
work runs under `daemon`. Both read machines and `.env` files again before each run: an edit
applies to the next run without a restart, and an edit that fails `decree check` is not used
until fixed (the old machines keep running and the errors are printed).

## The official plugins

A project may have added official plugins (`decree list` marks them `official`): `decree_develop`
(or its variants `decree_develop_rust`, `decree_develop_node` and `decree_develop_react`, which work as it does),
`decree_infra` and `decree_qa` below, `decree_router` (the default router), and `decree_newsletter`, `decree_comfy`,
`decree_develop_by_size`, `decree_gliner_router`, `decree_llm_router`, `decree_lease` and `decree_registry`, each described in
its plugin file. When one
of the three below is there, extend it (a plugin of the project's own with `extends`) before writing a machine of the same kind. Each starts with `clean_tree` (a root `onentry`: it fails the run
unless the git work tree is clean, naming each `interrupted` or `failed` run that may have left
the changes, with its `decree retry` and `git stash push` commands, also in its attention file) and
ends with `commit` (`done`'s `onentry`: the run's work as one commit, titled with the message's
first heading, and the order file for an order file's run, recorded in the same commit), or, in `failed`, with `keep` (the
run's changes stay in the work tree, and `keep` writes the run's `hold`, so its attention file
in `.decree/attention/` holds every run of their `worktree` group until the run is retried; other machines go on). All three touch only the
project folder. Before queuing work for them, commit or stash any changes. To continue: answer
any `STOP` in `plan.md`, delete `STOP`, `decree retry <id>`, which builds on the
kept changes and removes the hold. To drop the run: stash its changes and delete its
attention file. Never run `decree_develop`, `decree_infra` or `decree_qa` in two processes in one checkout (they
share the work tree through `clean_tree` and `commit`); give each its own git worktree. For divergent work,
or to keep editing while runs go on, suggest a
git worktree the user makes and runs decree in (`git worktree add ../app-exp -b exp`, then
`decree daemon --once` there): each checkout has its own runs and inbox, and its branch its own
`order.git.txt` records. A new worktree has committed files only: copy `.decree/.env` in and run
the project's infra plugin's `run.sh apply` (`.decree/machines/app_infra/scripts/run.sh apply`) there first.

`decree_develop`: `precheck` →
`implement` → `gate` → `verify`, with `fix` and `final_gate` only when the gate fails. Its scripts
source the `decree_ai` library's `ai.sh` (`ai`, which calls `ai_<backend>`: a data entry `ai_cli`, else
`AI_CLI`, else the first of `claude`, `opencode` and `copilot` on `PATH`) and
follow the run-directory files in `reference/scripts.md` (`progress.md`, `STOP`, `gate.log`,
`plan.md`): a person answers a `STOP` in `plan.md`, deletes `STOP` and
retries. `precheck` runs
`run.sh check` of the plugin that meets its `decree_infra` need, which checks every `.decree/machines/*/scripts/requirements`. `decree_develop`'s own gate runs nothing, says so and names `pass`: the project's plugin that extends it (or a variant) holds `scripts/gate.sh` with its own checks, kept by `decree export <name>` (or the next `commit`), and may hold `scripts/conventions.md`, which implement, fix and verify follow. The gate names `pass` (to `verify`) or `fail` (to `fix`,
then `final_gate`, whose `fail` ends the run); a non-zero exit means the checks could not run,
such as a missing tool, and goes to `failed` without `fix`. `ai.sh` runs the agent with
`DECREE_EVENT_FILE=/dev/null` and empties the caller's event file after it, so a gate the agent
runs names no event for its caller. `verify`
ends in `pass` or `fail` from the AI's `VERDICT:` line.

`decree_infra`: `declare` → `apply`, run through the project's own plugin that extends it
(`app_infra`; a message for `decree_infra` itself fails at once). The AI edits that machine's
`scripts/requirements` (`kind name version source`, one resource per line, in dependency
order), adding a kind in its `scripts/kinds/` only when none fits; `apply` runs its `run.sh
apply`, which installs what is missing and checks every line. The first infra order file builds
the environment; later ones add to it. Its `commit` exports the plugin, so the new lines are in
`.decree/plugins/app_infra.md` in the run's commit.

`decree_qa`: `recon` → `attack` → `run` → `triage` → `report`. The AI writes chaos tests in
`QA_DIR` (`tests/chaos`) against its `scripts/invariants.md`, each naming a wrench from
its `scripts/wrenches.md`; triage marks each real bug's tests with the framework's strict
expected-failure marker and writes one report per root cause (the broken invariant and the
expected behaviour, no fix), and `report` emits each as a message for the plugin that meets its `decree_develop` need. A guard (`scripts/qa.sh`) fails any step whose AI changed a file outside
`QA_DIR`. It does not start until `QA_RUN` in `scripts/qa.sh` of the project's plugin that extends it names the suite's command; once
decree_qa finds bugs, the gate should run it too.

## Worked example

An order file for the `feature` machine, `.decree/machines/feature/order/01-rate-limit-upload.md`:

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
# Graph: graph.md
name: hello
description: Run one script.
initial: greet
states:
  greet:
    invoke: greet                  # runs scripts/greet (or machines/hello/scripts/greet)
    transitions: { done: done }    # exit 0 -> done; non-zero -> failed, implicitly
  done:   { final: true }
  failed: { final: true }          # every machine has one
```

A machine grows one reason at a time. First, the straight line that does the job:

```yaml
# Graph: graph.md
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

- **`reference/messages.md`**: frontmatter keys, order files, the inbox,
  cron files, `decree emit`, replies to a waiting run.
- **`reference/machines.md`**: the graph line, every machine key, the invoke types, conditions, choices and
  routers, composition, events and transitions, validation rules, full examples.
- **`reference/scripts.md`**: where scripts live, how they run, how they report an event,
  every `DECREE_*` variable.
- **`reference/runs.md`**: run folders, `events.jsonl`, run status, waiting and interrupted
  runs, `decree retry`, graphs.

The reference files sit next to this file, in `reference/`.
