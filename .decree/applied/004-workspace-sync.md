---
machine: develop
---
# workspace/ stays in sync with a Nextcloud on another server

## Overview

Nextcloud often runs on a different server than the stack. The workspace still has to be the
same tree the user edits from their desktop, phone and Obsidian.

## Outcome

- With `EXIST_NEXTCLOUD_DOMAIN` and a Nextcloud user plus app password set, a decree cron
  two-way syncs `workspace/` with a folder in that Nextcloud every few minutes. When
  Nextcloud runs locally, the same setup works against it.
- The sync skips everything any `.gitignore` under `workspace/` ignores, and every `.git/`
  directory. Decree's run state therefore never syncs, and agent output can be kept local by
  ignoring it.
- Scripts under `workspace/.decree/scripts/` stay executable after a sync, even though WebDAV
  drops file modes.
- A sync that would delete an unusually large share of files stops and asks for a person
  instead of deleting them.

## Constraints

- The Nextcloud credentials live outside `workspace/`.
- Each new env key gets one informative comment line.

## Acceptance Criteria

- **Given** a file created in the remote Nextcloud folder
  **When** the next sync runs
  **Then** it appears in `volumes/workspace_data/`
- **Given** a path matched by a `.gitignore` under `workspace/`, or inside a `.git/`
  **When** a sync runs
  **Then** it is not uploaded
- **Given** a script synced down from Nextcloud
  **When** `decree check` runs in the workspace project
  **Then** it does not report the script as non-executable
