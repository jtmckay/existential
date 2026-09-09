---
sidebar_position: 1
---

# Decree

Decree is the automation engine at the heart of the Existential stack. It processes files,
integrates with cloud storage via rclone, reads from S3, and connects to external services
like Gmail.

Everything it runs is the same two things: a **routine** (a bash script that does one job) and a
**trigger** (something that decides when to run it). A trigger — a cron file, an HTTP POST, an
object landing in storage, another routine — produces a markdown message with `routine:` in its
frontmatter, and the daemon runs that routine with every other frontmatter key as an environment
variable. That is the whole model.

| To… | Read |
|---|---|
| Write your own automation | [Writing a Routine](../writing-a-routine) — anatomy, registration, triggers, chaining |
| Run something when a file appears | [File Change Processing](./file-change-processing) |
| Hand a task to a specific agent profile | [Routing to Departments](./routing) |
| See it all assembled on a real problem | [Note → Action](../flows/note-to-action) |
| Reach the stack from outside over HTTP | [Build On It](../build-on-it) |

## Running Decree

Two daemons run it, not one per service — `automation` (routing, AI work, every
service's one-time migrations) and `automation-backup` (backups only). Neither is
called `decree`; that's the binary inside them, not a container name.

### Connect to a running container

```bash
docker exec -it automation bash
```

### Manually trigger a routine

Decree has no `run` subcommand — drop a message into the inbox it drains instead:

```bash
printf -- '---\nroutine: <name>\n---\n' > automation/inbox/once.md
```

## Integrations

Gmail and rclone are configured through interactive setup scripts. See [Integrations](../integrations/) for setup instructions.

## S3 object storage

No manual credential setup — `automation`'s compose env already carries `S3_URL`,
`S3_ACCESS_KEY` and `S3_SECRET_KEY`, plus `S3_NEXTCLOUD_ACCESS_KEY` / `_SECRET_KEY` for the
bucket-scoped identity. Those names are deliberately product-neutral: they are mapped from
`SEAWEEDFS_*` in the compose file, so a routine never names the store it talks to. See [SeaweedFS](../storage/seaweedfs) for the bucket
side and [File Change Processing](./file-change-processing) for how routines reach it via rclone.
