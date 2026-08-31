---
name: decree
description: >
  Work within the Decree automation ecosystem — routines, cron jobs, hooks, inbox/outbox
  messages, and the backup daemon in automations/ and services/decree/.
  INVOKE when: user mentions automations/, decree, routines, cron jobs, hooks, inbox, outbox,
  or the decree container; user asks how to automate something, schedule a task, trigger a
  workflow, or process messages; user adds/modifies anything in automations/ or services/decree/.
  SKIP for: general shell scripting, Docker, or infrastructure work unrelated to decree.
---

# Decree Skill

Decree is an automation orchestrator. It processes inbox messages through configurable
routines, with lifecycle hooks and cron scheduling. In this repo decree runs as:

- **`decree`** (`services/decree/decree/`) — AI workflows, gmail, telegram, webhook-triggered
  tasks, service-health/triage, and **every service's one-time migrations**
- **`decree-backup`** (`services/decree/decree-backup/`) — backups only: `volume-backup`,
  `db-backup`, `sqlite-backup`, `workspace-sync`

That is the complete list. Services do **not** get their own `*-decree` sidecar any more; don't
add one. See `.claude/reference/services.md` for why, and for what each daemon can reach.

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
3. Which config to update — there are only two:
   - **Backup / volume-reading routines** — `services/decree/decree-backup/config.exist.yml`
   - **Everything else** (AI workflows, gmail, telegram, migrations, service crons) —
     `services/decree/decree/config.exist.yml`
   - **Notify / utility routines** — both, if either might use them

```yaml
# config.exist.yml
shared_routines:
  my-new-routine:
    enabled: true
```

## Activating a Cron Job

```bash
# <project> is decree or decree-backup
cp services/decree/<project>/cron.example/<name>.md services/decree/<project>/cron/<name>.md
# edit the copy to set schedule and parameters, then:
docker compose restart <project>
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

## Backups

All of them run in `decree-backup`, which mounts `volumes/` wholesale and takes the master
`.env` via `env_file` (with `DECREE_AI=` blanked — it installs no AI CLI). So **adding a backup
for a new service is one cron file** in `services/decree/decree-backup/cron.example/`: no
sidecar, no volume mount, no credential plumbing.

To trigger one now, drop a message in its inbox — `decree` has no `run` subcommand:
```bash
printf -- '---\nroutine: volume-backup\nTIER: nightly\nVOLUMES: |\n  my_volume my-container\n---\n' \
  > services/decree/decree-backup/inbox/manual-backup.md
docker logs -f decree-backup
```

Restores go through `./existential.sh run backup-restore`, which reads the active cron files'
`TARGETS`/`VOLUMES` blocks out of that same container.

## Reference Files

Read these when you need specifics — don't load all of them upfront:

- **`reference/routines.md`** — routine script structure, pre-check, custom params, registry config
- **`reference/hooks-and-cron.md`** — lifecycle hooks, firing semantics, cron scheduling
- **`reference/pipeline-and-vars.md`** — processing pipeline, all environment variables, run.json fields
- **`reference/migrations.md`** — migration format for AI development tasks (main decree only)

Reference files are at `.claude/skills/decree/reference/` relative to the project root.
