---
service: services/automation
sidebar_position: 1
---

# Decree

[Decree](https://github.com/jtmckay/decree) runs the stack's automations.

- A **script** is bash that does one job.
- A **machine** is a few lines of YAML naming the script and its params.
- A **trigger** (a cron file, an HTTP POST, a file change, another machine) produces a markdown
  message with `machine:` in its frontmatter, and the daemon runs that machine with the
  message's `params:`.

| To… | Read |
|---|---|
| Write your own automation | [Writing an Automation](../writing-a-routine) — machines, scripts, triggers, chaining |
| Run something when a file changes | [File Handlers](./file-handlers) |
| Hand a task to a specific agent profile | [Routing to Departments](./routing) |
| See it all assembled on a real problem | [Note → Action](../flows/note-to-action) |
| Reach the stack from outside over HTTP | [Build On It](../build-on-it) |

## Running Decree

- **`automation`**: routing, AI work, every migration.
- **[`automation-backup`](./automation-backup)** (off by default): backups, triage, and anything
  needing bulk volume access.

Each is its own decree project with its own runs.

```bash
docker exec automation decree status        # runs by state, and what is queued
docker exec automation decree status --cron # each cron file and when it fires next
echo | docker exec -i automation decree emit --machine <name>   # run one by hand
```

Every machine and chain is drawn in `automation/graph/system.md` (and
`services/automation-backup/graph/`).

## Claude for machines

You write machines by talking to Claude in code-server's terminal. Machines call AI in two ways:
- `model_chat` (`automation/lib/model.sh`) is one answer from the stack's own model endpoint.
- `agent` (`automation/lib/agent.sh`) is Claude Code, which can read and search your workspace.

The automation container comes with Claude Code installed. Sign it in once:

```bash
docker exec -it automation claude    # then /login, then /exit
```

The login is kept in `volumes/decree_data`. To use an API key or a `claude setup-token` token
instead, set `AUTOMATION_ANTHROPIC_API_KEY` or `AUTOMATION_CLAUDE_CODE_OAUTH_TOKEN` in
`services/automation/.env`, then `docker compose up -d`.

Once it is signed in:
- the [automations you write in a note](../flows/note-to-automation) are built by Claude rather
  than the chat model;
- a step of one can hand Claude a task;
- every call adds a line to `.decree/ai-use.md`;
- a call that hits Claude's usage limit waits for it to reset, up to six hours, and otherwise
  stops the run and tells you on ntfy.

A machine's Claude runs unattended in Claude Code's `auto` mode.

- It can't change your notes: the container sees them read-only, so an instruction hidden in an
  email or web page can't rewrite them.
- It can use everything else the container reaches: the rest of the workspace, automation's
  service credentials, the network. Output goes to `workspace/ai/`.
- `AUTOMATION_CLAUDE_PERMISSION_MODE=default` limits it to reading and searching.
- Calls go to Anthropic under your account's terms.

## When a run needs you

A run that fails or waits for a person sends one ntfy message on the `decree` topic, with the
machine, what happened, and the command to continue:

- failed: `docker exec automation decree process --retry <id>`
- waiting: `docker exec automation decree event <wait id> <option>`

One message per state. A failed `notify` run is never reported. `automation-backup` runs report
through [Grafana](../hosting/grafana)'s alert when monitoring is on.

## Integrations

Gmail and rclone have interactive setup scripts: [Integrations](../integrations/).

## File events

- A change matching a handler in `workspace/.decree/handlers.yml` runs its machine:
  [File Handlers](./file-handlers).
- Nextcloud uploads can post to the webhook's `/files` endpoint:
  [File Change Processing](./file-change-processing).
