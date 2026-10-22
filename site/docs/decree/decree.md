---
sidebar_position: 1
---

# Decree

[Decree](https://github.com/jtmckay/decree) is the automation engine at the heart of the
Existential stack. It processes files, integrates with cloud storage via rclone, and connects to
external services like Gmail.

Everything it runs is the same three things: a **script** (bash that does one job), a
**machine** (a few lines of YAML naming the script and the params it takes), and a **trigger**
(something that decides when to run it). A trigger — a cron file, an HTTP POST, a file landing
in Nextcloud, another machine — produces a markdown message with `machine:` in its frontmatter,
and the daemon runs that machine with the message's `params:` as its data. That is the whole
model.

| To… | Read |
|---|---|
| Write your own automation | [Writing an Automation](../writing-a-routine) — machines, scripts, triggers, chaining |
| Run something when a file appears | [File Change Processing](./file-change-processing) |
| Hand a task to a specific agent profile | [Routing to Departments](./routing) |
| See it all assembled on a real problem | [Note → Action](../flows/note-to-action) |
| Reach the stack from outside over HTTP | [Build On It](../build-on-it) |

## Running Decree

Two daemons run it, not one per service — `automation` (routing, AI work, every service's
one-time migrations) and `automation-backup` (backups, triage, and anything else that needs bulk
volume access). Each is its own decree project with its own runs. Neither is called `decree`;
that is the binary inside them.

```bash
docker exec automation decree status        # runs by state, and what is queued
docker exec automation decree status --cron # each cron file and when it fires next
echo | docker exec -i automation decree emit --machine <name>   # run one by hand
```

Every machine and how they chain is drawn in `automation/graph/system.md` (and
`services/automation/backup/graph/` for the other daemon), which GitHub renders.

## Integrations

Gmail and rclone are configured through interactive setup scripts. See [Integrations](../integrations/) for setup instructions.

## File events

No manual setup — Nextcloud posts every upload to the webhook's `/files` endpoint, and
machines read the file back through the `nextcloud` rclone remote. See
[File Change Processing](./file-change-processing).
