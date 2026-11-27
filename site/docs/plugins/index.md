---
sidebar_position: 1
---

# Plugins

:::info[The code you write]
What runs your automations, and how to write one. What they do for a person:
[What It Does](../flows/index.md). [Writing a Plugin](./writing-a-plugin.md) is the how-to;
[Over HTTP](./http.md) is the contract for reaching the stack from outside.
:::

Every machine the stack ships is a plugin: one file in `automation/plugins/<name>.md` holding
the machine, its scripts, the webhook endpoints that start it and, if it has one, its schedule.
It is a [decree plugin file](https://github.com/jtmckay/decree/blob/main/docs/reference/plugins.md),
which `decree install` installs, with this stack's own keys beside decree's, each `x-exist-…`.
An install has only the plugins it turned on, each at the version in its checkout. Pull the repo
and run `./existential.sh`, and every plugin you have on is the new version.

```markdown
---
name: my_plugin
needs: [model]          # the plugins it starts, emits to, or whose lib it uses
machine:                # the decree machine, without its name
  initial: start
  states: { … }
scripts:                # each becomes machines/my_plugin/scripts/<file>
  start.sh: |
    #!/usr/bin/env bash
    …
state:                  # yours to edit: each written once to store/my_plugin/<path>, never overwritten
  feeds.txt: |
    …
cron:                   # each becomes machines/my_plugin/cron/<file>, installed once
  my_plugin_nightly.md: |
    ---
    cron: "0 3 * * *"
    ---
x-exist-project: automation   # which decree project runs it: automation, backup or host (or a list)
x-exist-lib:            # each becomes .decree/lib/<path>, which its scripts source by that path
  my_plugin/helper.sh: |
    …
x-exist-endpoints:      # added to the webhook while it is installed
  - path: /my/{thing}
    message: { machine: my_plugin, params: { … } }
---
# My plugin

What it does and how to use it.
```

A plugin can also be one of [decree's own](https://github.com/jtmckay/decree/blob/main/docs/reference/plugins.md#official-plugins)
with your changes: `extends: decree_lease` and only the files it changes. That is how
`gpu_lease` is decree's `decree_lease` with this stack's GPU rules and swap script, and
`repo_develop` is decree's `decree_develop` with this repo's gate. decree's own plugins are
never edited in place; a plugin that extends one keeps your changes through every decree upgrade.

## Which ones you have

Every plugin is in that one folder, and its `x-exist-project` says which decree project runs it:

| `x-exist-project` | Where it is installed | What it runs |
|---|---|---|
| `automation` | `workspace/.decree` | everything that reasons, routes or calls a service |
| `backup` | `services/automation-backup/` | backups, triage, workspace sync |
| `host` | the repo's own `.decree` | what runs on the host itself, in [the host daemon](../hosting/host-daemon.md): [updates](../hosting/updates.md) |

None of them is on until you say so. What is on is each project's own list,
`.decree/plugins/.on`: the plugins you turned on there. Each project's `.decree/plugins/` gets
those, and whatever they need, at this checkout's version on every `./existential.sh`, and
`decree install` installs them; a repo plugin nothing on needs any more is removed. A project
never gets a plugin that is not tagged for it, and nothing the `automation` daemon runs, or a
model it calls, can write `backup`'s or the host's list. The installed copies (`plugins/`,
`machines/`, `lib/` in each project) are never committed; the plugin's file in the repo is the
one place it lives. A new install's `automation` list starts with `note_watch`, `reconcile`,
`service_health`, `pi`, `file_advise` and `you_were_here`.

A plugin with no machine is lib other plugins need: code they use (`model`, `pi`, `agent`,
`firecrawl`, `rss`, `fleet`) or a file processor (`ocr`, `transcribe`, `agent_handoff`). Every
helper a script uses is some plugin's `x-exist-lib`, installed into `workspace/.decree/lib/` and
sourced as `.decree/lib/<path>` (a script runs in the project's root). A plugin may also need one
of [decree's own](https://github.com/jtmckay/decree/blob/main/docs/reference/plugins.md#official-plugins),
named `decree_*`: `decree_order` (runs a plugin's one-time setup), `decree_ai` (Claude Code, for
`agent`); `decree_prune` prunes finished runs in every project. What a plugin needs that is not a
plugin (a service, a model, a step only you can do) is on its [What It Does](../flows/index.md)
page, or on the docs page of what it belongs to.

Data that is yours to edit (the newsletter's feeds and taste, pi's departments) is a plugin's
`state:`, written once to `workspace/.decree/store/<plugin>/` (each machine's `state/` is that
folder) and never overwritten, removed or sent to another stack. A plugin of
your own is a file in `workspace/.decree/plugins/`, installed with `decree install`
([Your Own Plugins](./offer-and-accept.md)). A schedule of your own is a plugin too, one with
only `cron:` files.

```bash
./existential.sh plugin                     # every plugin: on, + (something on needs it), or off
./existential.sh plugin on gpu_lease        # install it where its x-exist-project says, and keep it current
./existential.sh plugin off gpu_lease       # remove it, endpoints and schedule included
```

Turning a plugin off takes it out of its project's list; what it needed goes too, unless
something else on needs it.

## Changing one

On the host, change the installed machine and scripts in its project
(`volumes/workspace_data/.decree/machines/<name>/` for `automation`, also writable from
code-server) until it works, then write it back (`decree export`) and commit. A plugin that `backup` or the host
runs is exported from there, never from the workspace:

```bash
./existential.sh plugin export gpu_lease    # → automation/plugins/gpu_lease.md
```

Every install that has it on gets the new version on its next pull. A copy someone edited in
place is kept in `.decree/archive/<name>/` (decree does that) before the new version replaces
it. A schedule you edited in place is kept: decree installs a plugin's cron files once. Machines you wrote
yourself, and automations `develop` built from your notes, are never touched.

`notify` is the plugin system itself (with `skill` in the workspace, and decree's
`decree_prune`). It is a plugin file like the rest, but always installed, whatever is on, and only the repo's files install them: no
plugin you accept from another stack can replace it, nor one of decree's. Everything else is off until you turn it on.

## Between stacks

Off until `./existential.sh plugin on plugin_share plugin_offer`, which also needs
[automation-webhook](../decree/automation-webhook.md). With it on, another stack can ask yours for a
plugin, and yours can ask theirs. Nothing is installed anywhere without a person accepting it.

- `plugin_share`: another stack asks for one of your machines (`POST
  /plugins/<machine>/share/<client>`) and is sent it as a plugin file, at once for a machine you
  list in `PLUGIN_SHARE_ALLOW`, otherwise once you say yes on your phone. Asked for no machine
  (`POST /plugins/share/<client>`), it sends the list of your machines, each marked free or asks.
  A machine is sent as the plugin file it was installed from.
  Only clients with a `PLUGIN_SHARE_CALLBACK_<CLIENT>` in `automation/.env` (and its `_TOKEN`)
  can be sent anything.
- `plugin_request`: you ask another stack for its list, or for one machine. Set
  `PLUGIN_SHARE_NAME` (this stack's name, as the other stack knows it) and `PLUGIN_PEER_<FROM>`
  (its webhook's address) with `PLUGIN_PEER_<FROM>_TOKEN` in `automation/.env`, then `POST
  /request/plugins/<from>[/<machine>]`.
- `plugin_offer`: what comes back, at `/plugins/offer/<from>`. A list goes to your phone, with
  the line that asks for one; a plugin waits in `ai/proposed/` until you
  [install it](./offer-and-accept.md#offers). Read its scripts first: they run with this stack's access.

A plugin sent from another stack `needs:` the plugins it uses, which the receiving stack has to
have on: accepting it says which.
