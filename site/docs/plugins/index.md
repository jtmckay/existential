---
sidebar_position: 1
---

# Plugins

:::info[The code you write]
What runs your automations, and how to write one. Back to [Flows](../flows/index.md) for worked
examples. [Writing a Plugin](./writing-a-plugin.md) is the how-to;
[Over HTTP](./http.md) is the contract for reaching the stack from outside.
:::

Every machine the stack ships is a plugin: one file in `automation/plugins/<name>.md` holding
the machine, its scripts, the webhook endpoints that start it and, if it has one, its schedule.
An install has only the plugins it turned on, each at the version in its checkout. Pull the repo
and run `./existential.sh`, and every plugin you have on is the new version.

```markdown
---
machine: plugin
automation: gpu_lease
needs: [model]          # the plugins it starts, emits to, or whose lib it uses (export writes it)
chart:                  # the decree machine, without its name
  initial: start
  states: { … }
scripts:                # each becomes scripts/gpu_lease/<script>.sh
  start: |
    #!/usr/bin/env bash
    …
lib:                    # each becomes lib/<path>, reached as ${DECREE_LIB}/<path>
  gpu_lease/feeds.exist.txt: |   # an example of yours: copied once to feeds.txt
    …
cron:                   # each becomes cron/<name>.md
  gpu_lease_nightly: |
    ---
    machine: gpu_lease
    cron: "0 3 * * *"
    ---
endpoints:              # added to the webhook while it is installed
  - path: /gpu/{mode}/{client}
    message: { machine: gpu_lease, params: { … } }
---
# GPU lease

What it does and how to use it.
```

## Which ones you have

Three decree projects install plugins, each from the same folder:

| Project | Where | What it runs |
|---|---|---|
| `automation` | `workspace/.decree` | everything that reasons, routes or calls a service |
| `backup` | `services/automation-backup/` | backups, triage, workspace sync |
| `host` | `host/.decree` | what runs on the host itself: [updates](../hosting/updates.md) |

A project has exactly what its `.decree/plugins.yml` lists under `on:`, and whatever those need.
That file is yours, never in git, and written the first time from the project's
`plugins.exist.yml`: what every install starts with.

A plugin with no machine is a **flow**, in `automation/plugins/flows/`: one thing the stack does
for you, needing the plugins that do it and naming the services they use (turning it on asks before it
turns each on). Those with a
tagline are the ones [`./existential.sh flow`](../flows/index.md) offers; the rest are libraries, code
other plugins use (`model`, `pi`, `agent`, `firecrawl`, `rss`) or a file processor a flow turns
on (`ocr`, `transcribe`, `agent_handoff`). Every helper a script uses is some plugin's, installed into
`workspace/.decree/lib/` and reached as `${DECREE_LIB}/<path>`.

A file that is yours to edit (the newsletter's feeds and taste, the departments, the
agent-handoff criteria) ships as an example, `<name>.exist.<ext>`, and is copied to its real
name once. Your copy is never overwritten, removed or sent to another stack.

```bash
./existential.sh run plugin                     # the automation project's: on, installed, what each does
./existential.sh run plugin list host
./existential.sh run plugin on gpu_lease        # install it, and keep it current
./existential.sh run plugin off gpu_lease       # remove it, endpoints and schedule included
./existential.sh run plugin on host/update      # another project's
```

`plugins.yml` is `on: [...]` and `auto_update: true`. Turning a plugin off takes it out of `on:`;
one that something still on needs stays. With `auto_update: false`, a plugin whose file changed is named, not installed.

## Changing one

Change the installed machine, scripts and lib in `workspace/.decree/` until it works, then write
it back and commit:

```bash
./existential.sh run plugin export gpu_lease    # → automation/plugins/gpu_lease.md
```

Every install that has it on gets the new version on its next pull. A copy someone edited in
place is kept in `.decree/archive/` before the new version replaces it. Machines you wrote
yourself, and automations `develop` built from your notes, are never touched.

`notify` and the four `plugin` machines are the plugin system itself. They are not plugins: every
install has them, at the checkout's version, and no plugin can replace them.

## Between stacks

Another stack can ask yours for a plugin, and yours can ask theirs. Nothing is installed anywhere
without a person accepting it.

- `plugin_share`: another stack asks for one of your machines (`POST
  /plugins/<machine>/share/<client>`) and is sent it as a plugin file, at once for a machine you
  list in `PLUGIN_SHARE_ALLOW`, otherwise once you say yes on your phone. Asked for no machine
  (`POST /plugins/share/<client>`), it sends the list of your machines, each marked free or asks.
  Only clients with a `PLUGIN_SHARE_CALLBACK_<CLIENT>` in `automation/.env` (and its `_TOKEN`)
  can be sent anything.
- `plugin_request`: you ask another stack for its list, or for one machine. Set
  `PLUGIN_SHARE_NAME` (this stack's name, as the other stack knows it) and `PLUGIN_PEER_<FROM>`
  (its webhook's address) with `PLUGIN_PEER_<FROM>_TOKEN` in `automation/.env`, then `POST
  /request/plugins/<from>[/<machine>]`.
- `plugin_offer`: what comes back, at `/plugins/offer/<from>`. A list goes to your phone, with
  the line that asks for one; a plugin waits in `ai/proposed/`, and moving it into
  `notes/automations/` installs it. Read its scripts first: they run with this stack's access.

The file a stack sends names what it cannot carry, the `$DECREE_LIB` files its scripts use, which
the receiving stack has to have.
