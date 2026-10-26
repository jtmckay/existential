
## This project: file handlers

"When a file like X changes, do Y" is a machine plus a handler. The machine does Y and
declares `path` and `change` under `data:` (both strings; `path` is relative to the
workspace, `change` is `created`, `modified` or `deleted`). The handler is an entry in
`.decree/handlers.yml`, which is re-read on every change:

```yaml
- match: notes/to-process/*.md   # a glob, relative to the workspace
  machine: note_process
  changes: [created, modified]   # optional; default all three
  quiet: 30                      # optional; seconds with no further change before it runs
```

Suggest a folder or a pattern that keeps the handler off files the user isn't ready for
(drafts stay out of `to-process/` until they are done), and say that a `.gitignore` line
keeps a folder out of every handler. Nothing inside `.git/` and nothing a `.gitignore`
ignores ever fires one; beyond that, the handlers decide. A machine whose own output lands
on a path its handler matches will run on that output too: send output somewhere the
pattern does not reach.

Accepted automations from notes (`notes/automations/<name>.md`) are migrations for this
project's `develop` machine, filed into `.decree/migrations/` by `reconcile`. `develop`
builds `.decree/machines/<name>.yml`, `.decree/scripts/<name>.sh` and the trigger, and lists
it in `.decree/automations.yml`. All of that is rebuilt from the note on every edit: to change
one, edit its file in `notes/automations/`, never the built copies.

## This project: AI in a machine

A script reaches AI two ways, both in `.decree/lib/` (read-only, the stack's):

- `source "${DECREE_LIB}/model.sh"`, then `model_chat "<system>" "<user>"`: one answer from the
  stack's own model. Cheap, and always there.
- `source "${DECREE_LIB}/agent.sh"`, then `agent "<task>"`: Claude Code, run in the workspace in
  `auto` mode. `agent_ready` says whether this install has signed it in (`docker exec -it
  automation claude`, then `/login`). Use it for a step that has to look through files, act or
  reason at length.

In the `automation` container `notes/` is read-only: a machine reads notes and writes what it
makes under `ai/`, and one that writes a note fails.

`agent` is `ai` from `lib/ai.sh` with Claude chosen, which is what the rules above mean by
calling AI only through `ai`.
