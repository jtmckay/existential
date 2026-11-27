---
machine: repo_develop
---
# The stack reaches you through ntfy, and a failed or stuck automation says so

## Overview

An automation that dies silently is the failure every earlier system had: it needed you to go
and check. Core has no dashboards, so the stack itself has to say when something needs you,
through one channel.

## Outcome

- **ntfy is the only channel.** Every notification goes through the `notify` plugin to ntfy;
  nothing sends to or reads from Telegram or any other messenger.
- **One login.** Every publisher uses `EXIST_NTFY_USER`/`EXIST_NTFY_PASSWORD`, allowed to
  publish to every topic. `EXIST_NTFY_TOKEN`, `EXIST_NTFY_TOPICS` and `run ntfy setup` do not
  exist.
- **Every notification names its topic** (`decree emit --machine notify --param
  ntfy_topic=<topic>`), one of the Topics table on the ntfy docs page: `host`, `decree`,
  `suggestions`, `digest`, `exist`. A plugin doing the server's own work carries
  `x-exist-topic: host`, which routes its failed runs too. A new topic is a row there first.
- **A failed or stuck run tells you.** When a run in the workspace project fails or stops to
  wait on a person (a STOP, a `person` decision, a hold in `.decree/attention/`), ntfy sends
  one message naming the machine, what happened, and the one command that continues it. One
  message per run per state; the reporter can't report its own failure in a loop. On in a
  fresh install with nothing to set up beyond ntfy.
- **`service_health`** (a default) probes ntfy every 15 minutes and says when notifications
  stop getting through.

## Constraints

- No new service; it all runs in the automation container. Monitoring add-ons are not needed.

## Acceptance Criteria

- **Given** a machine whose script exits 1
  **When** it runs
  **Then** exactly one ntfy message names that machine and the retry command
- **Given** a run waiting in a `person` state
  **When** it starts waiting
  **Then** one ntfy message says it is waiting and how to answer
- **Given** `./existential.sh test plugins`
  **Then** every topic used is in the Topics table and every row is used
- **Given** the repo
  **When** `git grep -i telegram` runs outside `archive/` and `.decree/`
  **Then** nothing is found
