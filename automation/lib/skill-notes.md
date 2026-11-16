
## This project: you offer a plugin, a person accepts it

**You cannot create or change a machine, a script or lib here, and must not try.**
`.decree/machines/`, `.decree/scripts/` and `.decree/lib/` are read-only in every container
(this one included): only the host installs them. What you write instead is ONE plugin file,
`ai/proposed/<name>.md` (snake_case, 3-41 characters, not a name `ls .decree/machines` shows),
which holds the whole automation in its frontmatter:

```markdown
---
machine: plugin
automation: note_process
needs: [model]              # each installed plugin whose machine it emits to or whose lib it sources
chart:                      # the decree machine, without `name:`; start with one state
  description: What it does, in one line.
  data:
    path: {type: string, default: ""}
    change: {type: string, default: ""}
  initial: run
  states:
    run: {invoke: run, transitions: {done: done}}
    done: {final: true}
    failed: {final: true}
scripts:                    # each becomes scripts/<name>/<script>.sh
  run: |
    #!/usr/bin/env bash
    set -euo pipefail
    …
cron:                       # optional: each becomes cron/<key>.md
  note_process: |
    ---
    cron: "0 7 * * *"
    machine: note_process
    ---
handlers:                   # optional: file changes that start it (it then declares path and change)
  - match: notes/to-process/*.md   # a glob, relative to the workspace
    changes: [created, modified]   # default: created
    quiet: 30                      # seconds with no further change before it runs
when: a note about a business idea # optional: note_watch starts it for a note that is this
---
# note_process

What it is for, for the person who reads it before accepting.
```

Write the file, then tell the person, in these words: read `ai/proposed/<name>.md`, then on
the host run `./existential.sh run plugin accept <name>`. That command shows what the plugin
does and asks them; nothing runs before they say yes, and you cannot run it for them.
`decree check` here does not see an offer: check the YAML and `bash -n` each script yourself.
To change an accepted plugin, write the new version to `ai/proposed/<name>.md` again.

What you may write directly: notes, `ai/`, a message (`decree emit`, a file in `.decree/cron/`
that runs an installed machine), an entry in `.decree/handlers.yml` for an installed machine,
and data in `.decree/store/<machine>/` (the newsletter's `feeds.txt`, pi's departments).

A handler keeps off files the user isn't ready for (drafts stay out of `to-process/` until
they are done), and a `.gitignore` line keeps a folder out of every handler. Nothing inside
`.git/` and nothing a `.gitignore` ignores ever fires one. A machine whose own output lands
on a path its handler matches will run on that output too: send output somewhere the
pattern does not reach.

A note that says "next time X, do Y" is proposed as a spec in `ai/proposed/` (`machine:
develop`). Moving it into `notes/automations/` says "build this": `develop` builds it as a
plugin file, back in `ai/proposed/`, for the same review and the same `accept`.

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
