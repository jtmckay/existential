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
with its meaning, is in `.decree/schema/v1/events.schema.json`: read it.
Types:

| `type` | Meaning |
| --- | --- |
| `transition` | `from`, `event`, `to`, `source` (`claim`, `exit_code`, `script`, `attempt`, `check`, `model`, `reply`, `machine`, `timeout`, `internal`, `invalid_message`, `retry`). |
| `script` | One script finished: `state`, `phase`, `script`, `path`, `attempt`, `duration_ms`, `exit_code`, `log`. |
| `decision` | A `check`, `model` or `reply` produced its event: `kind`, `event`, and for models `pick`, `reason`, `confidence`, `router`, `child_run`. |
| `waiting` | Paused for a person (`wait_id`, `options`, `timeout_at`) or a child run (`child`). |
| `received` | A reply, a timeout or a child's result arrived. |
| `interrupted` | Stopped before a final state: `cause` is `signal` or `crash`. |
| `run_finished` | Reached a root final state: `state`, `duration_ms`. |

To find out why a run failed, read its `events.jsonl` from the end, then the log the last
`script` event names. `decree status <id>` shows the same as a table.

## Run status

| Status | Meaning | What to do |
| --- | --- | --- |
| `finished` | Reached a final state (`done`, `failed`, ...). | Nothing; for `failed`, what its file in `.decree/attention/` says, `decree retry <id>`; or that to run it again from a state. |
| `active` | A live process holds its lock. | `decree tail` to watch it. |
| `waiting` | Paused for a person, or for a child run. | `decree reply <wait id> <event>`; the run's file in `.decree/attention/` and `decree daemon --once` give the commands. `decree cancel <id>` if nobody will answer. |
| `pending` | A reply arrived, or a `retry` transition was written. | `decree daemon --once` continues it. |
| `interrupted` | Stopped by a signal or crash. | Fix the cause, then `decree retry <id>`, as its file in `.decree/attention/` says, or `decree cancel <id>` to drop it. decree never continues it on its own. |

A failed order file stops the order files after it: the `decree_order` run fails, and the next start
runs that file again. `decree daemon --once` exits 1 when a run failed in its pass, naming
`decree retry <id>` for each.

## Attention

`.decree/attention/<id>.md` is decree's list of what needs a person: a file per run that is
`failed`, `interrupted` or `waiting` in a `reply` state. Frontmatter `kind: run`, `run`, `machine`, `message`,
`status`, `state`, `since`, `holds` (`.decree/schema/v1/attention.schema.json`), then what
happened, the exact command (`decree retry <id>`, or one `decree reply <wait id>
<option>` per option), the run's `hold` text, its `leftovers` and its `STOP` question. decree
writes and deletes the files as each run's status changes; a file a person deleted stays deleted
until it changes again. `decree daemon --once` ends with `<n> run(s) need attention: .decree/attention/`, and
`decree status` starts with `Attention:` (`attention` in `--format json`).

- Read-only: answer with `decree reply` or a reply, continue with `decree retry`;
  editing a file answers nothing, and no script writes one.
- A file with `holds: true` (its run wrote `hold`) holds the runs of its machine's
  `concurrency_group` (or of the machine alone): they neither start nor continue, and the
  other machines go on. `pause.md`, or a `.md` file there that cannot be read as one (no
  frontmatter, invalid frontmatter), holds every run. `daemon --once` exits 1 naming it. `decree retry <id>` removes the run's `hold`
  and its file; deleting the file drops the run (stash its changes first), and decree then
  deletes the `hold`. Other files and subfolders there are ignored.

## Graphs

`decree graph` writes `.decree/machines/<machine>/graph.md` (a Mermaid `stateDiagram-v2`) for
each machine and `.decree/system.md` (machines, `emits` and `invokes` edges, cron entry points).
Edge labels say who decided: `(check)`, `(model)`, `(reply)`, `(machine: <name>)`; `(implicit)`
marks an unhandled `error` going to `failed`. Commit the files; they render on GitHub, GitLab,
Obsidian and in VS Code's Markdown preview (`Ctrl+Shift+V`), or paste the diagram into
https://mermaid.live.

Read a machine's graph before changing it, and run `decree graph` and `decree check` after.
