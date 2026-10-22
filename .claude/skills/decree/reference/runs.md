# Runs

One message moving through one machine is a run, stored in `.decree/runs/<id>/`:

```text
runs/<id>/
  message.md                 the claimed message; decree mirrors `state:` into it
  events.jsonl               one JSON line per event: the record and the telemetry
  traces.jsonl               one OTLP/JSON span per line, for OpenTelemetry tools
  0001-<state>-<script>.log  output of each script execution, numbered in run order
  request.json, reply.json   in a router's child run
  received/                  replies delivered to this run
  .lock, .running            the process stepping the run, and the script running now
```

## events.jsonl

The source of truth: the run's state is the `to` of its last `transition` event. Every line
carries `v`, `seq`, `ts`, `type`, `run_id`, `machine`, `trigger` and `trace_id`; `script`,
`decision` and `received` events, the claim and a `retry` carry the `span_id` of their span in
`traces.jsonl`. Every field of every type,
with its meaning, is in `.decree/schema/v1/events.schema.json`: run `decree schema`, then read it.
Types:

| `type` | Meaning |
| --- | --- |
| `transition` | `from`, `event`, `to`, `source` (`claim`, `exit_code`, `script`, `attempt`, `check`, `model`, `person`, `machine`, `timeout`, `internal`, `invalid_message`, `retry`). |
| `script` | One script finished: `state`, `phase`, `script`, `path`, `attempt`, `duration_ms`, `exit_code`, `log`. |
| `decision` | A `check`, `model` or `person` produced its event: `kind`, `event`, and for models `pick`, `reason`, `confidence`, `router`, `child_run`. |
| `waiting` | Paused for a person (`wait_id`, `options`, `timeout_at`) or a child run (`child`). |
| `received` | A reply, a timeout or a child's result arrived. |
| `interrupted` | Stopped before a final state: `cause` is `signal` or `crash`. |
| `run_finished` | Reached a root final state: `state`, `duration_ms`. |

To find out why a run failed, read its `events.jsonl` from the end, then the log the last
`script` event names. `decree status <id>` shows the same as a table.

## Run status

| Status | Meaning | What to do |
| --- | --- | --- |
| `finished` | Reached a final state (`done`, `failed`, ...). | Nothing; for `failed`, what its file in `.decree/attention/` says, `decree process --retry <id>`; or that to run it again from a state. |
| `active` | A live process holds its lock. | `decree tail` to watch it. |
| `waiting` | Paused for a person, or for a child run. | `decree event <wait id> <event>`; the run's file in `.decree/attention/` and `decree process` give the commands. |
| `pending` | A reply arrived, or a `retry` transition was written. | `decree process` continues it. |
| `interrupted` | Stopped by a signal or crash. | Fix the cause, then `decree process --retry <id>`, as its file in `.decree/attention/` says. decree never continues it on its own. |

A failed, interrupted or waiting migration blocks every later migration; `decree process` exits 1
ending ``Fix the cause, then run `decree process --retry`.`` (or 0 while only waiting). A
migration waiting for an interrupted child run counts as interrupted: the message names the
child, and `--retry` alone continues it. `decree status` shows the blocker under `Blocked:`.

## Attention

`.decree/attention/<id>.md` is decree's list of what needs a person: a file per run that is
`failed`, `interrupted` or `waiting` in a `person` state, and per migration waiting for an
interrupted child (naming the child). Frontmatter `kind: run`, `run`, `machine`, `message`,
`status`, `state`, `since`, `holds` (`.decree/schema/v1/attention.schema.json`), then what
happened, the exact command (`decree process --retry <id>`, or one `decree event <wait id>
<option>` per option), the run's `hold` text, its `leftovers` and its `STOP` question. decree
writes and deletes the files as each run's status changes; a file a person deleted stays deleted
until it changes again. `decree process` ends with `<n> run(s) need attention: .decree/attention/`, and
`decree status` starts with `Attention:` (`attention` in `--format json`).

- Read-only: answer with `decree event` or a reply, continue with `decree process --retry`;
  editing a file answers nothing, and no script writes one.
- While a file has `holds: true` (its run wrote `hold`), or a `.md` file there cannot be read
  as one (no frontmatter, invalid frontmatter), `process` and `daemon` start and continue no
  runs; `process` exits 1 naming it. `decree process --retry <id>` removes the run's `hold`
  and its file; deleting the file drops the run (stash its changes first), and decree then
  deletes the `hold`. Other files and subfolders there are ignored.

## Graphs

`decree graph` writes `.decree/graph/<machine>.md` (a Mermaid `stateDiagram-v2`) for each
machine and `.decree/graph/system.md` (machines, `emits` and `invokes` edges, cron entry points).
Edge labels say who decided: `(check)`, `(model)`, `(person)`, `(machine: <name>)`; `(implicit)`
marks an unhandled `error` going to `failed`. Commit the files; they render on GitHub, GitLab,
Obsidian and in VS Code's Markdown preview (`Ctrl+Shift+V`), or paste the diagram into
https://mermaid.live.

Read a machine's graph before changing it, and run `decree graph` and `decree check` after.
