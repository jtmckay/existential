---
name: decree
description: >
  Work within the Decree automation ecosystem — routines, cron jobs, hooks, inbox/outbox
  messages, and sidecar backup daemons in automations/ and services/decree/.
  INVOKE when: user mentions automations/, decree, routines, cron jobs, hooks, inbox, outbox,
  or the decree container; user asks how to automate something, schedule a task, trigger a
  workflow, or process messages; user adds/modifies anything in automations/ or services/decree/.
  SKIP for: general shell scripting, Docker, or infrastructure work unrelated to decree.
---

# Decree Skill

Decree is an automation orchestrator. It processes inbox messages through configurable
routines, with lifecycle hooks and cron scheduling. In this repo decree runs as:

- **Main daemon** (`decree` container) — AI workflows, gmail, telegram, webhook-triggered tasks
- **Per-service sidecars** (`<slug>-decree` containers) — backup routines scoped to one service

## Paths in This Repo

### Shared code (mounted read-only into every decree daemon)

| Host path | Container path | Purpose |
|---|---|---|
| `automations/shared_routines/` | `/work/.decree/shared_routines` | Routine shell scripts |
| `automations/lib/` | `/work/.decree/lib` | Shared helpers (precheck.sh, minio.sh, telegram.sh) |
| `automations/lib/hooks/` | via lib | Lifecycle hooks (afterEach.sh, config-watch.sh) |
| `automations/runs/` | `/work/.decree/runs` | Execution logs — all daemons write here |
| `automations/secrets/` | `/secrets` | rclone config, API keys |

### Per-daemon state (each daemon owns its own)

Main decree: `services/decree/decree/` → `/work/.decree`
Sidecars: `<category>/<slug>/decree/` → `/work/.decree`

```
<state-dir>/
├── config.exist.yml    Routine whitelist template (tracked, rendered → config.yml)
├── config.yml          Rendered config (gitignored — user overrides go here)
├── cron.example/       Cron templates (tracked, manually copied to activate)
├── cron/               Active cron triggers (gitignored)
├── inbox/              Message queue (gitignored — .gitkeep tracked)
├── outbox/             Follow-up messages (gitignored)
├── emails/             Archived email messages (gitignored, main decree only)
└── processed.md        Migration tracking (gitignored)
```

## Core Rules

- **Routines are the unit of work** — every automated task is a routine in `automations/shared_routines/`
- **Repeating work belongs to decree** — if something runs more than once (cron, webhook, inbox message) it is a routine, not a host cron job or `docker exec`
- **All routines are shared** — there are no daemon-local routines in this repo; everything lives in `automations/shared_routines/` and is selectively enabled per daemon via `config.exist.yml`
- **Outbox for follow-ups** — routines write follow-up messages to `.decree/outbox/`, not `.decree/inbox/`; decree relays outbox → inbox automatically
- **Bash first** — routines are bash scripts; reach for TypeScript only when bash becomes unworkable

## Adding a Routine

1. Create `automations/shared_routines/<name>.sh` (executable, `#!/usr/bin/env bash`, source `precheck.sh`)
2. Add it to every `config.exist.yml` that should see it:
   - `enabled: true` for routines on by default for that daemon
   - `enabled: false` for opt-in routines
3. Which configs to update:
   - **Backup routines** — every sidecar that owns a volume or DB
   - **Notify / utility routines** — every daemon that might use them
   - **Main-decree-only** (AI workflows, gmail, telegram) — only `services/decree/decree/config.exist.yml`

```yaml
# config.exist.yml
shared_routines:
  my-new-routine:
    enabled: true
```

## Activating a Cron Job

```bash
cp <state-dir>/cron.example/<name>.md <state-dir>/cron/<name>.md
# edit cron.example file to set schedule and parameters, then:
docker compose restart <slug>-decree
```

Cron files use YAML frontmatter. Extra frontmatter keys are passed as env vars to the routine:

```markdown
---
cron: "0 2 * * *"
routine: volume-backup
VOLUMES: "my_volume_name"
TARGETS: "minio:9000"
---
```

## Sidecar Pattern

Each backup-eligible service has a `<slug>-decree` sidecar. Sidecars:
- Mount only their own service's volumes (not the master `.env`)
- Receive only their own DB credentials via compose env vars
- Share `automations/shared_routines/`, `automations/lib/`, `automations/runs/`

To trigger a backup now:
```bash
docker exec <slug>-decree decree run db-backup -- nightly
docker exec <slug>-decree decree run volume-backup -- nightly
```

## Reference Files

Read these when you need specifics — don't load all of them upfront:

- **`reference/routines.md`** — routine script structure, pre-check, custom params, registry config
- **`reference/hooks-and-cron.md`** — lifecycle hooks, firing semantics, cron scheduling
- **`reference/pipeline-and-vars.md`** — processing pipeline, all environment variables, run.json fields
- **`reference/migrations.md`** — migration format for AI development tasks (main decree only)

Reference files are at `.claude/skills/decree/reference/` relative to the project root.
