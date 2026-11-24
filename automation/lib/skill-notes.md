---
name: existential
description: How a decree machine is made in this workspace (existential): you offer ONE plugin file in ai/proposed/, and a person accepts it on the host; you never install one. INVOKE when writing or changing a machine, script, cron file, file handler or plugin here, or when asked to automate something.
---

# This project: you offer a plugin, a person accepts it

Read the decree skill (`.claude/skills/decree/`) for decree itself. This is what is different here.

**You cannot create or change a plugin, a machine, a script or lib here, and must not try.**
`.decree/plugins/`, `.decree/machines/` and `.decree/lib/` are read-only in every container
(this one included): only the host installs them. What you write instead is ONE decree plugin
file, `ai/proposed/<name>.md` (snake_case, 3-41 characters, not a name `ls .decree/plugins`
shows, never `decree_*`), which holds the whole automation in its frontmatter. decree's own keys
are `name`, `extends`, `needs`, `machine`, `scripts`, `cron`, `state` and `order`; this
project's are `x-exist-*`:

```markdown
---
name: note_process
needs: [model]              # each installed plugin it emits to or whose lib it sources
machine:                    # the decree machine, without `name:`; start with one state
  description: What it does, in one line.
  data:
    path: {type: string, default: ""}
    change: {type: string, default: ""}
  initial: run
  states:
    run: {invoke: run, transitions: {done: done}}
    done: {final: true}
    failed: {final: true}
scripts:                    # each becomes machines/<name>/scripts/<file>
  run.sh: |
    #!/usr/bin/env bash
    set -euo pipefail
    …
cron:                       # optional: each becomes machines/<name>/cron/<file>
  note_process.md: |
    ---
    cron: "0 7 * * *"
    ---
x-exist-project: automation
x-exist-handlers:           # optional: file changes that start it (it then declares path and change)
  - match: notes/to-process/*.md   # a glob, relative to the workspace
    changes: [created, modified]   # default: created
    quiet: 30                      # seconds with no further change before it runs
x-exist-when: a note about a business idea  # optional: note_watch starts it for a note that is this
---
# note_process

What it is for, for the person who reads it before accepting.
```

Write the file, then tell the person, in these words: read `ai/proposed/<name>.md`, then on
the host run `./existential.sh run plugin accept <name>`. That command shows what the plugin
does and asks them; nothing runs before they say yes, and you cannot run it for them.
`decree check` here does not see an offer: check the YAML and `bash -n` each script yourself.
To change an accepted plugin, write the new version to `ai/proposed/<name>.md` again. To build on
one of decree's own (`decree_lease`, `decree_develop`...), write `extends: decree_<x>` instead of
a `machine:`, and only the scripts that change: never copy its scripts. A schedule for an
installed machine is a plugin too, one whose only key is `cron:` (each file naming its
`machine:`); there is no `.decree/cron/`.

What you may write directly: notes, `ai/`, a message (`decree emit`), an entry in `.decree/handlers.yml`
for an installed machine, and data in `.decree/store/<machine>/`, which is each machine's
`state/` (the newsletter's `feeds.txt`, pi's departments).

A handler keeps off files the user isn't ready for (drafts stay out of `to-process/` until
they are done), and a `.gitignore` line keeps a folder out of every handler. Nothing inside
`.git/` and nothing a `.gitignore` ignores ever fires one. A machine whose own output lands
on a path its handler matches will run on that output too: send output somewhere the
pattern does not reach.

A note that says "next time X, do Y" is proposed as a spec in `ai/proposed/` (`machine:
develop`). Moving it into `notes/automations/` says "build this": `develop` builds it as a
plugin file, back in `ai/proposed/`, for the same review and the same `accept`.

## This project: AI in a machine

A script runs in the project root, and reaches AI two ways, both in `.decree/lib/` (read-only,
the stack's):

- `source .decree/lib/model.sh`, then `model_chat "<system>" "<user>"`: one answer from the
  stack's own model. Cheap, and always there.
- `source .decree/lib/agent.sh`, then `agent "<task>"`: Claude Code, run in the workspace in
  `auto` mode. `agent_ready` says whether this install has signed it in (`docker exec -it
  automation claude`, then `/login`). Use it for a step that has to look through files, act or
  reason at length.

In the `automation` container `notes/` is read-only: a machine reads notes and writes what it
makes under `ai/`, and one that writes a note fails.

`agent` is `ai` from decree's `decree_ai` plugin (`.decree/machines/decree_ai/scripts/ai.sh`) with Claude
chosen, which is what the decree skill means by calling AI only through `ai`.
