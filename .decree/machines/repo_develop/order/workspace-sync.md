---
machine: repo_develop
---
# workspace/ can be kept the same as one other copy, on a NAS or in a Nextcloud

## Overview

The workspace has to be the same tree the person edits from a desktop, a phone and Obsidian,
and Nextcloud often runs on a different server than the stack.

## Outcome

- With automation-backup on and `./existential.sh plugin on workspace_sync`, `rclone bisync`
  runs every minute, both ways, with one other copy: a NAS folder
  (`EXIST_NFS_SHARE_WORKSPACE`, mounted by Compose; when set it is the only other copy) or a
  Nextcloud folder (`EXIST_NEXTCLOUD_DOMAIN`, `EXIST_NEXTCLOUD_USER`,
  `EXIST_NEXTCLOUD_APP_PASSWORD`, folder `EXIST_NEXTCLOUD_WORKSPACE_DIR`, default `workspace`).
  A file changed on both sides keeps the newer edit.
- Neither set: nothing syncs, nothing else notices, and the docs present sync as optional.
  With Nextcloud in this stack its `workspace` folder already is this tree.
- The sync skips everything any `.gitignore` under `workspace/` ignores, and every `.git/`.
  Decree's run state therefore never syncs, and agent output can be kept local by ignoring it.
- Scripts stay executable after a sync, even though WebDAV drops file modes.
- A sync that would delete over half the files on one side deletes nothing and waits for a
  person (`decree reply <wait id> delete` or `keep`).

## Constraints

- The Nextcloud credentials live outside `workspace/`.
- Each new env key has one informative comment line.

## Acceptance Criteria

- **Given** a file created in the remote Nextcloud folder
  **When** the next sync runs
  **Then** it appears in `volumes/workspace_data/`
- **Given** a path matched by a `.gitignore` under `workspace/`, or inside a `.git/`
  **When** a sync runs
  **Then** it is not uploaded
- **Given** `./existential.sh test workspace-sync`
  **Then** it exits 0
