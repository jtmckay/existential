# Machines

A machine is a statechart in `.decree/machines/<name>.yml`: a W3C SCXML document written in
YAML. Keys are SCXML's names (`initial`, `states`, `transitions`, `onentry`, `onexit`, `invoke`,
`data`, `final`); decree implements a strict subset of SCXML, plus a few marked extensions. If
you know SCXML, you know how a machine behaves.

The first line links the machine to its graph:

```yaml
# Graph: ../graph/<name>.md
```

**Before writing a machine, run `decree schema` and read `.decree/schema/v1/machine.schema.json`**
(generated, ignored by git): the precise contract for every key below, with a description and
examples for each. Write against it, then run `decree check`, which also checks what a schema
cannot: that names resolve, targets exist and every state is reachable. Editors apply the same
schema by path; machines carry no schema line.

## Keys

| Where | Key | Meaning |
| --- | --- | --- |
| Root | `name` | Equals the file stem; `^[a-z][a-z0-9_]*$`. |
| Root | `description` | Required. Shown in prompts, `decree status` and graphs. |
| Root | `data` | `name: { type: string\|int\|number\|bool, default: ..., enum?: [...] }`. `number` is an int or a float; `enum` (string only) lists the allowed values, which the default and `params` must be one of (V14). Read-only; a message's `params` override defaults. Scripts see `DECREE_DATA_<NAME>`. |
| Root | `store` | `name: description`: what the machine keeps between runs in `.decree/store/<machine>/` (`$DECREE_STORE`). A name is a file or folder directly in that folder, `^[A-Za-z0-9][A-Za-z0-9._-]*$`; a description says what it is and which states read or write it (V14). `decree check` warns about undeclared files there. |
| Root | `env_file` | `.env.<name>`: a gitignored dotenv file in `.decree/` whose variables this machine's scripts get, over `.decree/.env` and the process environment; no other machine's scripts see them (V14). |
| Root | `onentry`, `onexit` | Scripts run once when the run starts, and once after a root final state is entered. |
| Root | `initial`, `states` | Required. `initial` is a direct child. |
| State | `invoke` | The state's function (below). `attempts` and `timeout` go inside it. |
| State | `transitions` | `event: target`, or `event: { target, description, type: internal }`. |
| State | `onentry`, `onexit` | Scripts run every time the state is entered or exited. They produce no event. |
| State | `initial`, `states` | Make the state compound (no `invoke`). |
| State | `final: true` | A final state: only `description`, `onentry` and `emits` allowed. |
| State | `description` | Optional; the question context for a model. |
| State | `emits` | Extension. Machines this state's scripts may `decree emit` messages for. |

Inside a state, write keys in this order: `description`, `invoke`, `onentry`, `onexit`,
`transitions`, `emits`, then `initial` and `states` for a compound state. Don't write defaults
(no `attempts: 1`).

Every machine has a root-level final state named `failed`.

## Invoke: the state's function

`invoke` is a map with exactly one key, which names the kind. For `script` and `machine`, a bare
name is short for `{ name: <name> }`, and `invoke: implement` is short for
`invoke: { script: implement }`.

| `invoke` | What runs | Events |
| --- | --- | --- |
| `script: { name: <script>, attempts?: <n> \| [<value>, …], timeout?: <duration> }` | The script (see `scripts.md`), re-run in place while it fails, once per attempt (default 1), each stopped after `timeout`. A list gives each attempt its value in `$DECREE_ATTEMPT_VALUE`. | `done` (exit 0), `error` (non-zero), or the event it writes to `$DECREE_EVENT_FILE`. |
| `check: <condition>` | decree evaluates the condition. No AI. | `true` or `false`. |
| `model: { question: ..., router?: <machine>, min_confidence?: 0.8, output?: <state> }` | A router machine asks a model to pick one of the state's transitions. | An option; `unsure` below `min_confidence`; `error` if the router fails. |
| `person: { question: ..., ask: <script>, timeout?: <duration> }` | The `ask` script tells someone; the run pauses for a reply. | An option; `error` on timeout. |
| `machine: { name: <machine>, params?: {...} }` | The machine runs as a child run. | The child's root final state (`failed` becomes `error`). |

A duration (`timeout`, and `decree prune --older-than` and `decree daemon --interval`) is a whole
number followed by one unit, `s`, `m`, `h` or `d`: `90s`, `10m`, `12h`, `7d`. No fractions, no
combinations (`1h30m`) and no bare numbers.

A state with no `invoke` and a `done` transition passes straight through. Write decision invokes
in block style:

```yaml
  rounds_left:
    invoke:
      check: { visits: implement, less_than: { data: max_rounds } }
    transitions: { true: triage, false: review }   # true and false need no quotes
```

### Choices

For `model` and `person`, `question` is what is being decided, and the **options are the state's
transitions** except `unsure` and `error`. Every option needs a `description`: the question and
the descriptions are exactly what the model or person sees, so write them to stand alone. Write
prose (`question`, `description`) in block style, one key per line. Prose containing `: ` breaks
a plain YAML value: quote it (`description: "Step one: build"`) or use `description: >-` with the
text indented below.

A model sees only what it is given: the latest script output of the state named by `output`, and
the message body. Without `output`, it gets no script output at all. A script decides what a model
sees by what it prints, which is also how to keep secrets out of a prompt.

### Routers

A `model` state never calls a model itself. decree writes `request.json` (question,
options, the `output` state's output as `input`, message body, the run's history, and
`reply_schema`, a JSON Schema for the reply; `.decree/schema/v1/request.schema.json` after
`decree schema`) and runs a
**router**: an ordinary machine (`router:` on the invoke, else the machine named `router`, which
`decree init` writes).
Its script reads `$DECREE_REQUEST`, asks a model, and writes
`{"event": "...", "reason": "...", "confidence": 0.86}` to `$DECREE_REPLY`
(`.decree/schema/v1/reply.schema.json`). decree checks the
event is an option and applies `min_confidence`. To use another model, write another router
machine and point `router:` at it, or replace `machines/router.yml`; recalibrate `min_confidence` when you do.

Routers are **typed** or **untyped**. A typed router cannot answer outside the options: a
classifier such as GLiNER2.5-Decide picks one of the labels it is given, and a constrained
decoder (Ollama's `format`) is handed `reply_schema` unchanged. An untyped router asks a chat
model or coding agent (`claude -p`, Copilot, OpenCode) for free text, and its script must find
and check the JSON; its confidence is self-reported. Use a typed router for routing decisions
(cheap, frequent, bounded: which model, which path), and an untyped model for the work itself
and for judgments that need reasoning over a lot of context. [docs/routers.md](https://github.com/jtmckay/decree/blob/main/docs/routers.md)
shows both.

### Conditions

Typed objects: exactly one subject, exactly one operator.

| Subject | Value | Operators |
| --- | --- | --- |
| `output: <state>` | That state's latest script output, as logged. The state must invoke a script. | `matches` |
| `data: <name>` | A `data` value. | `<op>`; `matches` for string data |
| `visits: <state>` | Times that atomic state was entered in this run, since its last retry. | `<op>` |
| `confidence: <state>` | Confidence of that `model` state's latest decision, 0 to 1. | `<op>` |

`<op>`: `equals`, `not_equals`, `less_than`, `at_most`, `more_than`, `at_least`. `<value>` is a
literal or `{ data: <name> }`; `int` and `number` data compare numerically. For example `{ output: read_text, matches: '(?i)invoice' }`. No
`and`/`or`: use two `check` states in a row.

## Events and transitions

- A script's event: `done`, `error`, or a name it writes to `$DECREE_EVENT_FILE`. Writing `done`
  is the same as writing nothing. Any other named event that is reserved or matches no transition
  becomes `error`.
- Selecting a transition: the current state's `transitions`, then each ancestor's, innermost
  first. An `error` nobody handles goes to `failed`; any other unhandled event becomes `error`.
- Event names match `^[a-z][a-z0-9_]*(\.[a-z0-9_]+)*$`. Scripts and options may not use
  `error`, `unsure`, or names starting with `done.` or `error.`, and options may not be `done`. A `check` produces `true` or
  `false`; YAML reads `true:` and `false:` as booleans, and decree reads them as those events.
  `yes` and `no` are ordinary event names (decree reads YAML 1.2, so they stay strings).
- A **compound state** loops among its children until it enters its own final child, which
  raises `done.state.<id>`; handle it on the compound (`transitions: { done.state.work: done }`).
- `onexit` runs from the innermost state outward, `onentry` from the outermost inward, as SCXML
  does. A self-transition exits and re-enters.

## Two kinds of retry

| | `attempts` | A transition back (`retry`) |
| --- | --- | --- |
| Means | "That crashed; run it again." | "That worked but the result is wrong; do another round." |
| Leaves the state? | No: no `onexit`/`onentry`, no new visit | Yes: `visits` + 1 |
| Bounded by | `attempts` in the script invoke | A `check` on `visits` |

`attempts` is a number, or a list whose entries run in order, each as `$DECREE_ATTEMPT_VALUE`,
until one attempt does not end in `error`:

```yaml
implement:
  invoke:
    script: { name: implement, attempts: [local, local, claude, local], timeout: 3h }
  transitions: { done: verify, error: ask_person }   # all four failed: a person
```

Entries match `^[A-Za-z0-9][A-Za-z0-9._:/@-]{0,127}$` (`claude-opus-5-5`, `qwen3:8b`). Use a list
when the same step is only done by something else (a stronger model); use a transition to another
state when what happens next differs. Each new visit starts again at attempt 1.

Only `error` (a non-zero exit or a timeout) runs the next attempt. `done`, or any event the
script names, such as `stop`, ends the list at once and goes to the state's `transitions`.

A stronger model answering a weaker one's `STOP` is not an attempt: transition to a child
machine.

```yaml
implement:
  invoke:
    script: { name: implement, attempts: [local, local] }
  transitions: { done: gate, stop: escalate }
escalate:                        # a stronger model answers the local model's question
  invoke:
    machine: { name: escalate }
  transitions: { answered: implement }
```

The child reads `$DECREE_PARENT_RUN_DIR/STOP`, appends the answer to
`$DECREE_PARENT_RUN_DIR/plan.md` for the next `implement` visit, deletes `STOP` and ends in
`answered`; a child that ends in `failed` reaches the parent as `error`, which goes to `failed`
implicitly. Every caller must handle a child's final states, so keep them few.

## Not supported (and the alternative)

`cond` on transitions (make the decision a `check` state), `<parallel>`, `<history>`, `<send>`
(use `decree emit`), `<raise>` (a script names its event), `<assign>` (`data` is read-only),
targetless transitions, XML. `decree check` names the alternative when it rejects one, and names
the new shape for an old one (`choose`, `input`, a bare `matches`, the old retry key (now `attempts`),
`timeout_s` on a state, `timeout_s` in an invoke, `{ machine: x, params: ... }`).

## Example: everything at once

```yaml
# Graph: ../graph/feature.md
name: feature
description: Implement one feature spec with an AI agent, verify it, and commit.
data:
  max_rounds: { type: int, default: 2 }
onentry: [clean_tree]              # root onentry: when the run starts, and again on a retry
onexit: [notify]                   # root onexit: once, after a root final state is entered
initial: precheck
states:
  precheck:
    invoke: precheck
    transitions: { done: work }
  work:                            # compound: the implement/verify loop as one unit
    transitions: { done.state.work: done }   # raised when work reaches its own final state
    initial: implement
    states:
      implement:
        invoke:                    # attempts: re-run a crashing script in place
          script: { name: implement, attempts: 2 }
        onexit: [collect_logs]
        transitions: { done: verify }
      verify:                      # script: names pass or fail
        invoke: verify
        transitions: { pass: verified, fail: rounds_left }
      rounds_left:                 # deterministic check: true or false
        invoke:
          check: { visits: implement, less_than: { data: max_rounds } }
        transitions: { true: triage, false: review }
      triage:                      # a model picks one option; below the floor it is unsure
        invoke:
          model:
            question: Should we implement again or split the work?
            min_confidence: 0.8
            output: verify
        transitions:
          retry:  { target: implement, description: The failures look fixable; implement again. }
          split:  { target: spawn_followups, description: The scope is too large; emit smaller follow-up messages. }
          unsure: review
      review:                      # a person picks one option; the run pauses for the reply
        invoke:
          person:
            question: Tests still fail. What next?
            ask: ask_person
            timeout: 2d
        transitions:
          approve: { target: verified, description: Good enough; commit it. }
          retry:   { target: implement, description: Try again; see my note. }
          reject:  { target: failed, description: Stop. }
      verified: { final: true }    # raises done.state.work
  spawn_followups:
    invoke: spawn
    transitions: { done: done }
    emits: [feature]               # extension: machines its scripts may emit messages for
  done:   { final: true, onentry: [commit] }   # migrations: processed.md is written first, so the commit includes it
  failed: { final: true }
```

## Example: composing machines

```yaml
# Graph: ../graph/ship.md
name: ship
description: Implement a feature, then deploy it.
initial: build
states:
  build:
    invoke: { machine: feature }
    transitions: { done: release }
  release:
    invoke: { machine: deploy }
    transitions: { done: done, rejected: done }
  done:   { final: true }
  failed: { final: true }
```

## Escalation

Decide the cheapest way first and pass on only what is undecided: `false` from a `check`, `unsure`
from a `model` below its `min_confidence`, then a `confidence` check to decide whether a
person's time is worth it, then `person`. Each threshold is a number in the machine.

## Validation

`decree check` runs rules V1–V21 (names, targets, `failed` exists, reachability, every script
name resolves, decision states cover their events, options have descriptions, `emits` and
`router` name real machines, no invoke cycles, nothing outside the SCXML subset) and M1–M3 (every
pending migration, inbox message and cron file parses and names a machine with valid `params`)
and E1 (`.decree/.env` and each `env_file` are valid dotenv files without reserved keys). Errors look like `machines/feature.yml: work.verify: <message>`. It also warns when
`.decree/graph/` is out of date, or `.decree/schema/` when it exists: run `decree graph` or
`decree schema`.
