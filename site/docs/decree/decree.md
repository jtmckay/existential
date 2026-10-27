---
service: services/automation
sidebar_position: 1
---

# Decree

[Decree](https://github.com/jtmckay/decree) is the automation engine at the heart of the
Existential stack. It processes files, integrates with cloud storage via rclone, and connects to
external services like Gmail.

Everything it runs is the same three things: a **script** (bash that does one job), a
**machine** (a few lines of YAML naming the script and the params it takes), and a **trigger**
(something that decides when to run it). A trigger — a cron file, an HTTP POST, a file changing
in the workspace, another machine — produces a markdown message with `machine:` in its frontmatter,
and the daemon runs that machine with the message's `params:` as its data. That is the whole
model.

| To… | Read |
|---|---|
| Write your own automation | [Writing an Automation](../writing-a-routine) — machines, scripts, triggers, chaining |
| Run something when a file changes | [File Handlers](./file-handlers) |
| Hand a task to a specific agent profile | [Routing to Departments](./routing) |
| See it all assembled on a real problem | [Note → Action](../flows/note-to-action) |
| Reach the stack from outside over HTTP | [Build On It](../build-on-it) |

## Running Decree

Two daemons run it, not one per service — `automation` (routing, AI work, every service's
one-time migrations) and, when you turn it on, [`automation-backup`](./automation-backup)
(backups, triage, and anything else that needs bulk volume access). Each is its own decree project with its own runs. Neither is called `decree`;
that is the binary inside them.

```bash
docker exec automation decree status        # runs by state, and what is queued
docker exec automation decree status --cron # each cron file and when it fires next
echo | docker exec -i automation decree emit --machine <name>   # run one by hand
```

Every machine and how they chain is drawn in `automation/graph/system.md` (and
`services/automation-backup/graph/` for the other daemon), which GitHub renders.

## Claude for machines

AI comes in at two places. You talk to Claude in code-server's terminal, and that conversation
is how new machines get written. Machines then call AI themselves while they run, in one of two
ways:
- `model_chat` (`automation/lib/model.sh`) is one answer from the stack's own model endpoint.
- `agent` (`automation/lib/agent.sh`) is Claude Code, which can read and search your workspace.

The automation container comes with Claude Code installed. Sign it in once:

```bash
docker exec -it automation claude    # then /login, then /exit
```

The login is kept in the container's home folder, `volumes/decree_data`, so it survives a
rebuild. To use an API key instead, or a token from `claude setup-token`, set
`AUTOMATION_ANTHROPIC_API_KEY` or `AUTOMATION_CLAUDE_CODE_OAUTH_TOKEN` in
`services/automation/.env`, then run `docker compose up -d`.

Once it is signed in:
- the [automations you write in a note](../flows/note-to-automation) are built by Claude rather
  than the chat model;
- a step of one can hand Claude a task;
- every call adds a line to `.decree/ai-use.md`;
- a call that hits Claude's usage limit waits for it to reset, up to six hours, and otherwise
  stops the run and tells you on ntfy.

A machine's Claude runs with nobody there to say yes, so it acts on its own (Claude Code's
`auto` mode). One thing it can never change is your notes, which are what you tell the stack
to do: the automation container sees them read-only. A note, an email or a web page can hide
an instruction, and this way such an instruction can never rewrite what you asked for.
Everything else the container reaches, it can use: the rest of the workspace, the
service credentials automation holds, the network. What machines write goes to
`workspace/ai/`. `AUTOMATION_CLAUDE_PERMISSION_MODE=default` keeps Claude to reading and
searching. Calls go to Anthropic under your account's terms.

## When a run needs you

A run in `workspace/.decree` that fails, or stops to wait for a person, sends one ntfy message
on the `decree` topic. The message names the machine and what happened, and gives the command
that continues the run: `docker exec automation decree process --retry <id>` for a failed run,
or one `docker exec automation decree event <wait id> <option>` per answer. A run sends one
message per state, so a run that stays failed doesn't send it again. Nothing to set up beyond
ntfy itself.

It comes from what decree already writes to `.decree/attention/`, read every few seconds by
`automation/lib/attention-notify.sh` in the `automation` container. A failed `notify` run is never
reported, so a broken ntfy can't loop. Backup runs (`automation-backup`) report through
[Grafana](../hosting/grafana)'s alert when monitoring is on.

## Integrations

Gmail and rclone are configured through interactive setup scripts. See [Integrations](../integrations/) for setup instructions.

## File events

The `automation` container watches the workspace, and a change to a file a handler in
`workspace/.decree/handlers.yml` matches runs that handler's machine. See
[File Handlers](./file-handlers). With Nextcloud in the stack, its uploads can also post to
the webhook's `/files` endpoint: [File Change Processing](./file-change-processing).
