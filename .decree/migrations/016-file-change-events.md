---
machine: develop
---
# File handlers: a change to a matching file in the workspace starts an automation

## Overview

Automations should react to the user's files directly: drop a PDF in a folder, or finish a
note, and what should happen happens. Today only uploads through Nextcloud fire file events,
which makes Nextcloud mandatory for the most natural trigger there is. The workspace is a
local volume on the same host, so the stack can see every change itself, whoever made it.

Deciding what should not trigger is the user's job, done with handlers and folders (keep a
draft out of `to-process/` until it's ready), not something the stack guesses.

## Outcome

- Every file change anywhere in the workspace is evaluated: created, modified, moved or
  deleted, whether code-server, Obsidian through a sync, a script or the host made it.
- A path any `.gitignore` in the workspace ignores, or anything inside a `.git/` directory,
  never fires a handler, whatever the handler matches. This is the same rule the sync uses,
  and it keeps decree's own run state from ever triggering a handler.
- Handlers live in `workspace/.decree/handlers.yml`. Each handler names a path pattern (a
  glob, so an extension like `**/*.pdf` or a folder like `notes/to-process/*.md`), optionally
  which changes it cares about, and the machine to run. A change matching no handler does
  nothing. A change matching several handlers runs each of them.
- A handler fires once the file has been quiet: no further change to it for 30 seconds, by
  default, set per handler. An editor's autosaves while you type reset the clock, so the
  handler runs once, after you stop. A deleted file fires without waiting.
- Each run gets the file's workspace-relative `path` and the `change` (`created`, `modified`
  or `deleted`).
- The watcher starts with the stack, survives restarts, and picks up `handlers.yml` edits
  without one.
- The shipped `notes/my-first-note.md` has one line saying a change to a matching file can
  start an automation, and that `.gitignore` keeps a folder out of it.
- The decree skill's project notes tell Claude that "when a file like X changes, do Y" means
  a machine plus a handler, and to suggest a folder or pattern that keeps it from running on
  files the user isn't ready for.
- The Nextcloud file-event path keeps working, and docs describe Nextcloud as optional sync,
  not the trigger. `CLAUDE.md`'s loop-break note describes the new rule.

## Constraints

- No new image. The watcher runs inside the existing automation containers or as a service
  built from the same image, named with the `automation-` prefix.
- Nothing is watched outside the workspace.
- Beyond `.gitignore` and `.git/`, the stack filters nothing on the user's behalf: the
  handlers decide.

## Acceptance Criteria

- **Given** a handler for `notes/to-process/*.md`
  **When** a file there is written five times within ten seconds, then left alone
  **Then** exactly one run starts, about 30 seconds after the last write, with `path` and
  `change` set
- **Given** a handler for `**/*.pdf`
  **When** a PDF is copied anywhere in the workspace
  **Then** one run starts for it
- **Given** a handler for `**/*.md` and a `.gitignore` in the workspace that ignores `scratch/`
  **When** `scratch/a.md` changes
  **Then** no run starts
- **Given** a file matching no handler
  **When** it changes
  **Then** no run starts
- **Given** an edit to `handlers.yml`
  **When** a file matching the new handler changes
  **Then** the new handler runs, with no restart
