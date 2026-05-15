---
name: decree
description: >
  Work within the Decree automation ecosystem — routines, cron jobs, hooks, inbox/outbox
  messages, and migrations in automations/.
  INVOKE when: user mentions automations/, decree, routines, cron jobs, hooks, inbox, outbox,
  or the decree container; user asks how to automate something, schedule a task, trigger a
  workflow, or process messages; user adds/modifies anything in automations/ or services/decree/.
  SKIP for: general shell scripting, Docker, or infrastructure work unrelated to decree.
---

# Decree Skill

Decree is an AI orchestrator for structured, reproducible workflows. It processes
ordered migration files through configurable routines, with lifecycle hooks and
cron scheduling.

**Loaded via:** `/decree` slash command (project or user scope).

## Core Rules

- **Ordered by filename** — use numeric prefix (`01-add-feature.md`)
- **Immutable once processed** — never edit a migration in `.decree/processed.md`; create a new one instead
- **Self-contained** — independently implementable, no sibling runtime dependencies
- **One concern per migration** — day-sized; a migration spanning five subsystems is five migrations
- **Always set `routine:`** — required frontmatter field; check `automations/config.yml` or run `decree routine`
- **Acceptance criteria required** — Given / When / Then with observable outcomes (exit codes, file contents, HTTP responses — not "works correctly")
- **All changes go through migrations** — no direct repo edits outside the workflow; if a script is needed by later migrations, create a migration for it first

## Project Patterns

### Outbox (follow-up messages)
Routines must write follow-up messages to `.decree/outbox/`, **not** directly to `.decree/inbox/`.
Decree relays `outbox/ → inbox/` automatically. Writing directly to inbox bypasses the relay.

### This project's paths
- Working directory: `automations/` (mounted at `/work/.decree` in the container)
- Routines: `automations/routines/`
- Hooks: `automations/hooks/`
- Cron: `automations/cron/`
- Config: `automations/config.yml`

## Reference Files

Read these when you need specifics — don't load all of them upfront:

- **`reference/migrations.md`** — migration format, acceptance criteria, sizing, immutability, placement
- **`reference/routines.md`** — routine script structure, pre-check, custom params, registry config
- **`reference/hooks-and-cron.md`** — lifecycle hooks, firing semantics, cron scheduling
- **`reference/pipeline-and-vars.md`** — processing pipeline, all environment variables, run.json fields

Reference files are at `.claude/skills/decree/reference/` relative to the project root.
