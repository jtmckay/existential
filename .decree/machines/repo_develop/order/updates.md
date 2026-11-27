---
machine: repo_develop
---
# Staying up to date without thinking about it

## Overview

A system you have to remember to upgrade gets left behind. Three host plugins keep the
install, its images and an Ubuntu host current, and say so only when something needs the person.

## Outcome

- `pull_existential`: every 15 minutes, fast-forward only, it pulls, runs `./existential.sh`
  (which installs the new version of every plugin that is on) and `docker compose up -d`, then
  deletes images no container uses. The phone hears an update, and a pull that could not
  fast-forward, which changes nothing.
- `check_versions`: Fridays at noon, one notification listing every pinned image or base image
  with a newer version upstream (`./existential.sh run check-versions`).
- `update_ubuntu`: Sundays at 01:00 `apt-get upgrade` (nothing removed, the release never
  changes), and a reboot at 02:00 only when one is required; daily security updates are Ubuntu's
  own `unattended-upgrades`. The phone hears a failure and a coming reboot.
- All three are host plugins (`x-exist-project: host`), off until `plugin on`, run by the host
  daemon, each with `x-exist-topic: host`.
- Guide: *It Looks After Itself*, Staying up to date; Technical: *Updates*.

## Constraints

- Without them, upgrading is `git pull && ./existential.sh && docker compose up -d`.
- A pull never rewrites local history: fast-forward or nothing.

## Acceptance Criteria

- **Given** `./existential.sh test update`
  **Then** it exits 0
- **Given** `./existential.sh validate conventions`
  **Then** it passes: each of the three has its `plugin on` line on a docs page
