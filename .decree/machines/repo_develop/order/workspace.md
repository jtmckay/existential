---
machine: repo_develop
---
# One folder, workspace/: your notes, what the stack writes, and a decree project Claude already knows

## Overview

The person works in one folder: `workspace/` (the `workspace_data` volume), holding `notes/`,
`ai/` and `.decree/`. They write notes in code-server's editor (or Obsidian, through a sync),
then start Claude in the same folder and say what they want automated. Claude must already
know how to write a decree machine, with nothing to install. Notes are what a person tells the
stack to do, so nothing the stack runs may change them.

## Outcome

- A fresh workspace has `notes/my-first-note.md`, a short note explaining the loop in the
  person's terms (write here; start Claude here and say what should happen; it becomes an
  automation; install ntfy on your phone to hear back; a change to a matching file can start
  an automation, and `.gitignore` keeps a folder out of it). It is written once and never
  overwritten.
- The workspace root has the decree skill (`.claude/skills/decree/`, as `decree skill --ai
  claude` writes it) and this stack's own beside it (`.claude/skills/existential/`), refreshed
  when the decree version changes; files the person added there are kept.
- code-server opens `/workspace` by default.
- `workspace/.decree` is the `automation` project: writable in every container that mounts the
  workspace (automation, code-server, Nextcloud, automation-backup); what is written there
  runs with no restart. Each installed machine's `graph.md` is mermaid, readable in the
  editor.
- **No automation changes a note.** In the `automation` container `workspace/notes/` is
  mounted read-only. What a machine makes goes to `workspace/ai/` (the digest, look backs,
  research, offers in `ai/proposed/`).
- `workspace/.decree/.gitignore` ignores run state (runs, store, inbox, attention, logs).
- The Guide's Your Workspace page says what each folder holds and where to open it.

## Constraints

- Nothing in the workspace depends on Nextcloud or Obsidian.
- No secret is ever written under `workspace/`: rclone config, tokens and `.env` files stay in
  `automation/` and `/secrets`.

## Acceptance Criteria

- **Given** a fresh install
  **When** the stack starts
  **Then** `volumes/workspace_data/notes/my-first-note.md` and
  `volumes/workspace_data/.claude/skills/decree/SKILL.md` exist
- **Given** an edited `notes/my-first-note.md`
  **When** the stack restarts
  **Then** the edit is still there
- **Given** a running stack
  **When** `docker exec automation touch /workspace/notes/x` runs
  **Then** it fails with a read-only file system
