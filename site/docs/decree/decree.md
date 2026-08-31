---
sidebar_position: 1
---

# Decree

Decree is the automation engine at the heart of the Existential stack. It processes files,
integrates with cloud storage via rclone, reads from S3/MinIO, and connects to external services
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

### Connect to a running container

```bash
docker compose run decree bash
```

### One-off run (without daemon)

```bash
docker compose run --rm decree decree process
```

## Integrations

Gmail and rclone are configured through interactive setup scripts. See [Integrations](../integrations/) for setup instructions.

## Configure S3

Set your MinIO (or AWS S3) credentials in `services/decree/.env`:

```bash
S3_ENDPOINT=http://minio:9000
S3_ACCESS_KEY=your_access_key
S3_SECRET_KEY=your_secret_key
S3_BUCKET=your_bucket
```
