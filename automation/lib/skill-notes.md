---
name: existential
description: How a decree machine is made in this workspace (existential): ONE plugin file in .decree/plugins/, installed with decree install. INVOKE when writing or changing a machine, script, cron file, file handler or plugin here, or when asked to automate something.
---

# This project: a machine is one plugin file

Read the decree skill (`.claude/skills/decree/`) for decree itself. This is what is different here.

A machine is ONE decree plugin file, `.decree/plugins/<name>.md` (snake_case, 3-41
characters, never `decree_*`), which holds the whole automation in its frontmatter. decree's own keys
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
---
# note_process

What it is for, in a sentence or two.
```

Write the file, then `decree install <name>` and `decree check`: it runs from then on. To change
it, edit the file and `decree install <name>` again (an edit made in `.decree/machines/` is
archived by the next install). A plugin the repo ships (`.decree/plugins.tsv` lists its machines, on or off) is rewritten
on the host's next run: change only your own. To turn one of yours off, delete its file and run
`decree install`; one of the repo's is turned off on the host, `./existential.sh plugin off <name>`. To build on one of decree's own
(`decree_lease`, `decree_develop`...), write `extends: decree_<x>` instead of a `machine:`, and
only the scripts that change: never copy its scripts.

A file change starts a machine through an entry in `.decree/handlers.yml` (`match` a glob
relative to the workspace, `machine`, `changes` default `[created]`, `quiet` seconds), which
works at once; the machine then declares `path` and `change` in its `data:`. (`x-exist-handlers`
and `x-exist-when` in the plugin also work, once the host next runs `./existential.sh`.) A schedule for an
installed machine is a plugin too, one whose only key is `cron:` (each file naming its
`machine:`); there is no `.decree/cron/`.

Data a machine keeps is in `.decree/store/<machine>/`, which is each machine's
`state/` (the newsletter's `feeds.txt`, pi's departments).

A handler keeps off files the user isn't ready for (drafts stay out of `to-process/` until
they are done), and a `.gitignore` line keeps a folder out of every handler. Nothing inside
`.git/` and nothing a `.gitignore` ignores ever fires one. A machine whose own output lands
on a path its handler matches will run on that output too: send output somewhere the
pattern does not reach.

A note that says "next time X, do Y" is proposed as a spec in `ai/proposed/` (`machine:
develop`). Moving it into `notes/automations/` says "build this": `develop` builds it as a
plugin file, back in `ai/proposed/`, which a person reads and moves into `.decree/plugins/`.

## This project: AI in a machine

A script runs in the project root, and reaches AI two ways, both in `.decree/lib/` (the
stack's):

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
