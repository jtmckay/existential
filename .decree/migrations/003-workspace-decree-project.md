---
machine: develop
---
# The stack's decree project lives in workspace/.decree

## Overview

The user works in one folder: `workspace/`, holding `notes/` (an Obsidian vault) and `.decree/`.
Automations the user asks an agent to write should land where the user already looks, sync
like any other file, and show their state-machine graphs in Obsidian, since they are mermaid
in markdown. Today the stack's decree project is the repo's `automation/` folder, which the
user never sees.

## Outcome

- The `automation` daemon and `automation-webhook` run the decree project at
  `workspace/.decree` (inside the `workspace_data` volume). Machines, scripts, migrations,
  cron and inbox written there run with no restart.
- The machines and scripts the repo ships reach `workspace/.decree` on first start, and are
  never overwritten afterwards. The user's edits win, the same contract as rendered files.
  The shared helpers (`automation/lib`) stay owned by the repo and stay current with it.
- `workspace/.decree/graph/` is regenerated whenever a machine changes, so Obsidian shows the
  current graphs.
- `workspace/.decree/.gitignore` ignores run state (runs, store, inbox, attention, logs). Every
  other file there is meant to sync.
- The `automation-backup` project keeps working.
- Quests, e2e, docs and validators that name `automation/migrations` or `automation/cron` name
  the new location, and `./existential.sh test decree` checks the shipped machines.

## Constraints

- No secret is ever written under `workspace/`. rclone config, tokens and `.env` files stay
  outside it.
- `/repo` stays mounted only in `automation-backup`.

## Acceptance Criteria

- **Given** a fresh install with Core enabled
  **When** the stack starts
  **Then** `volumes/workspace_data/.decree/machines/` holds the shipped machines and
  `docker exec automation decree status` succeeds
- **Given** a machine edited in `workspace/.decree/machines/`
  **When** the daemon next ticks
  **Then** `workspace/.decree/graph/<machine>.md` reflects the edit
- **Given** the test suites
  **When** `./existential.sh test` runs
  **Then** it exits 0
