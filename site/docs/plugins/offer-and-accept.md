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

It installs the repo's plugins (`automation/plugins/`, the ones on) into the same folder, and
leaves a plugin file it did not write alone. The ones it wrote are listed in
`.decree/plugins/.existential` and are rewritten at the checkout's version on every run: change
your own, not those.

`automation-backup` and the host install only the repo's plugins. Nothing written in the
workspace runs there.

## What starts it

- A `cron:` file in the plugin.
- A file change: an entry in `.decree/handlers.yml` naming the machine, which works at once.
  `x-exist-handlers` in the plugin, and `x-exist-when` (a kind of note, for `note_watch`), are
  wired the next time `./existential.sh` runs on the host.
- A message: `decree emit --machine <name>`.

## Offers

Something the stack writes on its own still waits for you. [`note-to-automation`](../flows/note-to-automation.md)'s
`develop` and another stack (the [`plugin-sharing`](./index.md#between-stacks) flow) write a plugin
file to `workspace/ai/proposed/<name>.md`, and your phone says so. Read it: its scripts run in the
`automation` container with that container's credentials. To install it:

```bash
mv ai/proposed/<name>.md .decree/plugins/ && decree install <name>
```

## Changing or removing one

Edit the file and `decree install <name>` again. To remove one, delete its file and run
`decree install`.
