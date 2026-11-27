---
sidebar_position: 1.5
---

# Your Own Plugins

A machine of your own is one plugin file in the workspace, installed from the workspace:

```bash
# in code-server's terminal, in /workspace
$EDITOR .decree/plugins/<name>.md      # the machine, its scripts, its cron (the format: ./index.md)
decree install <name> && decree check   # installed; the automation daemon runs it from now on
```

`claude`, `opencode` or `pi` in code-server do the same when you ask one for an automation.
`workspace/.decree/` is writable in every container that mounts the workspace: `automation`,
code-server, Nextcloud and `automation-backup`.

## What `./existential.sh` does with yours

It installs the repo's plugins (`automation/plugins/`, the ones on) into the same folder, at the
checkout's version on every run, and leaves alone any plugin file whose name is not one of the
repo's. Give yours a name of its own: one the repo ships is refused.

`automation-backup` and the host install only the repo's plugins. Nothing written in the
workspace runs there.

## What starts it

- A `cron:` file in the plugin.
- A file change: an entry in `.decree/handlers.yml` naming the machine, which works at once.
  `x-exist-handlers` in the plugin, and `x-exist-when` (a kind of note, for `note_watch`), are
  wired the next time `./existential.sh` runs on the host.
- A message: `decree emit --machine <name>`.

## Offers

Something the stack writes on its own still waits for you. `develop` ([below](#built-from-a-note))
and another stack ([plugin sharing](./index.md#between-stacks)) write a plugin file to
`workspace/ai/proposed/<name>.md`, and your phone says so. Read it: its scripts run in the
`automation` container with that container's credentials. To install it:

```bash
mv ai/proposed/<name>.md .decree/plugins/ && decree install <name>
```

Moving a plugin file into `notes/automations/` installs nothing.

## Built from a note

*Next time…* in a note ([Tell It Once](../flows/tell-it-once.md)) becomes an offer through four
machines, all on by default:

| Step | Machine | What happens |
|---|---|---|
| A note settles | `note_watch` | The [file handler](./file-handlers.md) for `notes/**/*.md` runs it a minute after the last save. One model call asks two things: is there a standing instruction here ("next time…", "whenever…"), and is this note the event an automation you accepted is waiting for? |
| A standing instruction | `automation_propose` | The model writes a spec (Overview, Outcome, Constraints, Acceptance Criteria) to `ai/proposed/`, and you are told. Nothing is built. |
| You say "build this" | `reconcile` | Moving the spec to `notes/automations/<name>.md` hands it to `develop`. The spec stays the automation's desired state. |
| It is built, as an offer | `develop` | The model answers with the trigger and the steps, written as one plugin file: a machine, its script, and the trigger as `when:` (a note event), `handlers:` (a file change) or `cron:`. It must pass `decree check` in a scratch copy, and a file trigger may never match its own output. A failed check goes back to the model once; a second failure reaches your phone. The file goes to `ai/proposed/<name>.md`. |
| It runs | `<name>` | Once you install it. It writes to `ai/automations/<name>/<date>-<note>.md` and sends the first lines to ntfy. |

- The model writes only a `steps` function. The frame around it gives it the triggering note or
  file, `ask` (one chat model answer), `web_search` and `web_read` ([Firecrawl](../ai/firecrawl.md);
  with Firecrawl off, steps that use them are refused), `curl` and `jq`.
- Steps that need a person (pay, sign up, send, decide) come back under "For you".
- `develop` uses Claude when the automation container is
  [signed in](../decree/decree.md#claude-for-machines), otherwise the chat model.
- Notes are read-only to the automation container, so nothing it reads can rewrite them.

## Changing or removing one

Edit the file and `decree install <name>` again. To remove one, delete its file and run
`decree install`. For one built from a note, edit its spec in `notes/automations/` and a new
version is offered; deleting the spec removes nothing.
