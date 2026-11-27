---
machine: repo_develop
---
# Notes that find their own connections

## Overview

The person writes something down, not knowing they solved the same problem three weeks ago.
Each new note is checked against everything already written.

## Outcome

- `note_connect` asks pi, in a department that can search the notes (qmd), for one
  non-obvious connection between a new or changed note and what is already there; one that
  clears the bar is written to its output folder (`OUTPUT_DIR`, in automation's own data),
  copied beside the source note when `CONNECT_OUTPUT_RCLONE_DEST` is set, and the phone says so.
- The first run marks what exists as seen; `CONNECT_BOOTSTRAP=true` checks the backlog once.
- Guide: *Pick Up the Thread*, Notes that find their own connections.

## Constraints

- Notes are read-only; nothing leaves the box but the model call to the configured address.

## Acceptance Criteria

- **Given** `./existential.sh test pi`
  **Then** it exits 0
- **Given** `./existential.sh validate conventions`
  **Then** it passes
