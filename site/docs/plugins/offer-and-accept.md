---
sidebar_position: 1.5
---

# Offer and Accept

Nothing made inside the stack runs until you have read it and said yes on the host. This is the
one way a new automation gets in, whoever wrote it: a model, an agent in code-server, another
stack, or you.

```
  in the workspace                         on the host
  ────────────────                         ───────────
  a plugin file is written to       →      ./existential.sh run plugin accept <name>
  workspace/ai/proposed/<name>.md          shows what it runs, asks you, installs it
        (an offer)                               (the only thing that can)
```

## Why it works this way

The `automation` container hands what it reads (your notes, web pages, email) to a model, and
code-server runs agents with a shell. Either can be talked into writing something you did not
ask for. So decree's code is out of their reach:

- `workspace/.decree/plugins/`, `machines/` and `lib/` are **read-only in every container that
  mounts the workspace**: `automation`, code-server, Nextcloud (so a synced desktop cannot change
  them either) and `automation-backup`. `workspace-sync` never carries them in or out.
- Only `./existential.sh`, on the host, installs into them (`decree install`), and only from
  `automation/plugins/`. decree never installs on its own.
- What a container *can* write is data and messages: notes, `ai/`, a cron file or inbox message
  for a machine that is already installed, a handler, and `.decree/store/` (your feeds, your
  departments). None of those is code.

## The journey

1. **Something writes an offer.** One plugin file, `workspace/ai/proposed/<name>.md`: the machine,
   its scripts and what starts it, all in the frontmatter ([the format](./index.md)). It comes from:
   - [`note-to-automation`](../flows/note-to-automation.md): you write "next time X, do Y", approve
     the plain-words spec by moving it into `notes/automations/`, and `develop` builds the plugin;
   - `claude`, `opencode` or `pi` in code-server, when you ask one for an automation;
   - another stack, with the [`plugin-sharing`](./index.md#between-stacks) flow on;
   - you, writing the file by hand.
2. **Your phone says so**, with where to read it and the command.
3. **You read it.** It is one file. The scripts in it will run in the `automation` container with
   that container's credentials.
4. **You accept it, on the host:**

   ```bash
   ./existential.sh run plugin offers          # what is waiting
   ./existential.sh run plugin accept <name>   # what it starts on, needs and runs; then asks
   ```

   `accept` needs a terminal and a typed `y`. There is no flag that says yes for you, and nothing
   in a container can run it.
5. **It is installed and on.** The file is kept in `automation/plugins/local/` (never in git) and
   installed into the workspace project like any plugin. `./existential.sh run plugin off <name>`
   turns it off.

## What accept will not do

- Install into `automation-backup` or the host: an accepted plugin is `x-exist-project: automation`,
  whatever the file says.
- Replace a plugin the repo ships, one of decree's, or `notify`.
- Keep a plugin that fails its checks (an endpoint that starts another machine, a failed
  `decree install` or `decree check`): it is put back out and the offer stays.

## Changing or removing one

A new version is a new offer under the same name: `accept` shows what changes before it asks.
For one `develop` built, edit its spec in `notes/automations/` and `develop` offers it again.
Deleting the spec removes nothing; `./existential.sh run plugin off <name>` does.

An automation an older install built in place keeps running, and is never rebuilt: have it
offered again to change it.
