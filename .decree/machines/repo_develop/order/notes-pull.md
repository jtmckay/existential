---
machine: repo_develop
---
# A notes vault kept somewhere else, pulled in

## Overview

Some people keep their vault on a NAS or another machine and don't want to move it. It is
pulled into `workspace/notes/`, where everything else already looks.

## Outcome

- `notes_pull` rsyncs an external vault (`user@nas:/path/to/vault/` in its cron file) into
  `workspace/notes/` every 15 minutes, one way, without `--delete` unless asked, with its own SSH
  key in `automation/secrets/notes-pull/`.
- It runs in `automation-backup` (`x-exist-project: backup`), never in `automation`.
- Guide: *Everything in One Place*, Your notes vault.

## Constraints

- One way only: nothing is ever written back to the source.

## Acceptance Criteria

- **Given** `./existential.sh validate conventions`
  **Then** it passes: `plugin on notes_pull` is on a docs page
