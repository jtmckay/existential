---
machine: repo_develop
---
# Every service checked on a schedule

## Overview

Each service already carries its own check. Running them on a schedule turns a service that
quietly broke into one notification, and another when it recovers.

## Outcome

- `triage` runs every enabled service's `exist.test.sh` and notifies on the `host` topic when
  one breaks and when it recovers. Nothing to configure: what is on is what is checked.
- It runs in `automation-backup`, which has the repo read-only; by hand,
  `./existential.sh test services`.
- Guide: *It Looks After Itself*, Every service checked.

## Constraints

- Checks are read-only ([[01-services]]): running them changes nothing.

## Acceptance Criteria

- **Given** every service folder (`<category>/<slug>/docker-compose.exist.yml`)
  **Then** it has an `exist.test.sh`
