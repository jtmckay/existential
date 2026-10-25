---
machine: develop
---
# A fresh install has a workspace: notes/ and a decree project Claude already knows

## Overview

The user works in one folder: `workspace/`, holding `notes/` (plain markdown) and `.decree/`.
They write notes in code-server's editor (or Obsidian, optionally), then start Claude in the
same folder and say what they want automated. Claude must already know how to write a decree
machine, with nothing for the user to install. Automations land where the user already looks,
and their graphs are mermaid in markdown, readable in the editor or Obsidian.

## Outcome

- A fresh install's workspace has `notes/my-first-note.md`, a short note that explains the
  loop in the user's terms (write here; start Claude here and say what should happen; it
  becomes an automation in `.decree/`; install ntfy on your phone to hear back). It is
  written once and never overwritten.
- The workspace root has the decree skill for Claude (`.claude/skills/decree/`, as
  `decree skill --ai claude` writes it), so `claude` started in `/workspace` in code-server
  knows how to write machines for this project. It is refreshed when the stack's decree
  version changes; files the user added to that folder are kept.
- code-server opens `/workspace` by default.
- The `automation` daemon and `automation-webhook` run the decree project at
  `workspace/.decree` (inside the `workspace_data` volume). Machines, scripts, migrations,
  cron and inbox written there run with no restart.
- The machines and scripts the repo ships reach `workspace/.decree` on first start, and are
  never overwritten afterwards. The user's edits win, the same contract as rendered files.
  The shared helpers (`automation/lib`) stay owned by the repo and stay current with it.
- `workspace/.decree/graph/` is regenerated whenever a machine changes.
- `workspace/.decree/.gitignore` ignores run state (runs, store, inbox, attention, logs).
- The `automation-backup` project keeps working.
- Flows, e2e, docs and validators that name `automation/migrations` or `automation/cron` name
  the new location, and `./existential.sh test decree` checks the shipped machines.

## Constraints

- Nothing in the workspace depends on Nextcloud or Obsidian.

- No secret is ever written under `workspace/`. rclone config, tokens and `.env` files stay
  outside it.
- `/repo` stays mounted only in `automation-backup`.

## Acceptance Criteria

- **Given** a fresh install with Core enabled
  **When** the stack starts
  **Then** `volumes/workspace_data/.decree/machines/` holds the shipped machines and
  `docker exec automation decree status` succeeds
- **Given** a fresh install
  **When** the stack starts
  **Then** `volumes/workspace_data/notes/my-first-note.md` and
  `volumes/workspace_data/.claude/skills/decree/SKILL.md` exist
- **Given** an edited `notes/my-first-note.md`
  **When** the stack restarts
  **Then** the edit is still there
- **Given** a machine edited in `workspace/.decree/machines/`
  **When** the daemon next ticks
  **Then** `workspace/.decree/graph/<machine>.md` reflects the edit
- **Given** the test suites
  **When** `./existential.sh test` runs
  **Then** it exits 0
