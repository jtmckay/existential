---
name: decree
description: >
  Work within the Decree automation ecosystem — routines, cron jobs, hooks, inbox/outbox
  messages, and the backup daemon in automation/ and services/automation/.
  INVOKE when: user mentions automation/, decree, routines, cron jobs, hooks, inbox, outbox,
  or the decree container; user asks how to automate something, schedule a task, trigger a
  workflow, or process messages; user adds/modifies anything in automation/ or services/automation/.
  SKIP for: general shell scripting, Docker, or infrastructure work unrelated to decree.
---

# Decree Skill

Decree is an automation orchestrator. It processes inbox messages through configurable
routines, with lifecycle hooks and cron scheduling. In this repo decree runs as:

- **`decree`** (`services/automation/decree/`) — AI workflows, gmail, telegram, webhook-triggered
  tasks, service-health/triage, and **every service's one-time migrations**
- **`decree-backup`** (`services/automation/backup/`) — backups only: `volume-backup`,
  `db-backup`, `sqlite-backup`, `workspace-sync`

That is the complete list. Services do **not** get their own `*-decree` sidecar any more; don't
add one. See `.claude/reference/services.md` for why, and for what each daemon can reach.

## Paths in This Repo

### The main daemon: one wholesale mount

`automation/` (repo root) IS `/work/.decree` for the `automation` (main decree) daemon — the
whole directory is bind-mounted in one shot, not per-subdirectory. It contains everything the
daemon's project needs, and nothing that isn't:

```
automation/
├── shared_routines/    Routine shell scripts, shared with the backup daemon
├── lib/                Shared helpers (precheck.sh, minio.sh, telegram.sh) + hooks/
├── runs/                Execution logs — both daemons write here (gitignored)
├── secrets/             rclone config, API keys (gitignored; also mounted separately at /secrets)
├── cron/                Active cron triggers (gitignored)
├── migrations/          Active one-time migrations (gitignored)
├── inbox/               Message queue (gitignored — .gitkeep tracked)
├── outbox/              Follow-up messages (gitignored)
├── processed.md         Migration tracking (gitignored)
└── router.md            The router prompt (tracked)
```

`automation-examples/` (repo root, sibling to `automation/`) holds the tracked cron/migration
**templates** — `cron/` and `migrations/` — manually copied into `automation/cron/` or
`automation/migrations/` to activate. It is never mounted: templates aren't runtime content.

**Several things are layered read-only on top of the wholesale mount, not part of the writable
bulk of it:**

- `shared_routines/` and `lib/` — this container runs `agent-task` with terminal and write
  access, so the routine scripts themselves must not be writable from inside a routine. A
  compromised or misbehaving run could otherwise rewrite the code every future run (and
  `automation-backup`, which shares the same `shared_routines/`/`lib/`) executes.
- `cron/`, `migrations/`, and `router.md` — nothing at runtime ever writes to these; they're
  only ever written from the host (a human/quest copying from `automation-examples/`, or
  `exist.initial.sh`, before the container starts), so there's no reason for the container to
  hold write access.
- **`config.yml`/`config.exist.yml`, which also don't live at the root at all** —
  they stay in `services/automation/decree/`, because the render pipeline
  (`src/templates.sh`) and `validate-conventions.ts` both look specifically for
  `<slug>/decree/config.exist.yml`; moving it to the repo root would silently stop it from ever
  being rendered or validated. It's layered in at `./decree/config.yml:/work/.decree/config.yml:ro,z`.

What's left genuinely writable in `/work/.decree`: `inbox/`, `outbox/`, `runs/`, `secrets/`,
`processed.md`, `precheck.log`, `config.hash` — decree's own dequeue/tracking state and every
routine's follow-up messages.

`opencode.json` and `migration-gate.sh` (mounted as `exist.test.sh`) also stay outside the
wholesale mount — they're compose-level integration files, not decree project content.

`services/automation/decree/` also holds the **image build** — `Dockerfile`, `entrypoint.sh`,
`package.json`, `pnpm-lock.yaml`, `pnpm-workspace.yaml` — since the old per-project state dir
that used to live there moved out to the root.

### The backup daemon: per-subdirectory mounts, own project dir

`decree-backup` doesn't get the wholesale treatment — its crons are per-instance, not shared
mounted content, so `services/automation/backup/` keeps the classic shape:

```
services/automation/backup/
├── config.exist.yml    Routine whitelist template (tracked, rendered → config.yml)
├── config.yml          Rendered config (gitignored — user overrides go here)
├── cron.example/       Cron templates (tracked, manually copied to activate)
├── cron/               Active cron triggers (gitignored)
├── lib/, shared_routines/, runs/   Mount points for automation/lib, /shared_routines, /runs (ro)
└── inbox/              Message queue (gitignored — .gitkeep tracked)
```

It mounts `automation/shared_routines/`, `automation/lib/`, `automation/runs/` individually
(read-only) and `automation/secrets/` at `/secrets` (read-only) — the same shared code the main
daemon uses, just not wholesale.

## Core Rules

- **Routines are the unit of work** — every automated task is a routine in `automation/shared_routines/`
- **Repeating work belongs to decree** — if something runs more than once (cron, webhook, inbox message) it is a routine, not a host cron job or `docker exec`
- **All routines are shared** — there are no daemon-local routines in this repo; everything lives in `automation/shared_routines/` and is selectively enabled per daemon via `config.exist.yml`
- **Outbox for follow-ups** — routines write follow-up messages to `.decree/outbox/`, not `.decree/inbox/`; decree relays outbox → inbox automatically
- **Bash first** — routines are bash scripts; reach for TypeScript only when bash becomes unworkable

## Adding a Routine

1. Create `automation/shared_routines/<name>.sh` (executable, `#!/usr/bin/env bash`, source `precheck.sh`)
2. Add it to every `config.exist.yml` that should see it:
   - `enabled: true` for routines on by default for that daemon
   - `enabled: false` for opt-in routines
3. Which config to update — there are only two:
   - **Backup / volume-reading routines** — `services/automation/backup/config.exist.yml`
   - **Everything else** (AI workflows, gmail, telegram, migrations, service crons) —
     `services/automation/decree/config.exist.yml`
   - **Notify / utility routines** — both, if either might use them

```yaml
# config.exist.yml
shared_routines:
  my-new-routine:
    enabled: true
```

## Activating a Cron Job

```bash
# decree (main daemon) — templates and active crons are both top-level
cp automation-examples/cron/<name>.md automation/cron/<name>.md
# edit the copy to set schedule and parameters, then:
docker compose restart automation

# decree-backup — templates and active crons stay in its own project dir
cp services/automation/backup/cron.example/<name>.md services/automation/backup/cron/<name>.md
docker compose restart automation-backup
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
for a new service is one cron file** in `services/automation/backup/cron.example/`: no
sidecar, no volume mount, no credential plumbing.

To trigger one now, drop a message in its inbox — `decree` has no `run` subcommand:
```bash
printf -- '---\nroutine: volume-backup\nTIER: nightly\nVOLUMES: |\n  my_volume my-container\n---\n' \
  > services/automation/backup/inbox/manual-backup.md
docker logs -f automation-backup
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
