---
machine: develop
---
# A failed or stuck automation tells you on ntfy

## Overview

An automation that dies silently is the failure every earlier system had: it needed you to go
and check. Core has no dashboards, so the stack itself has to say when something needs you.
This is one of the automations Core ships ready to run.

## Outcome

- When a decree run in the workspace project fails, or stops to wait on a person (a STOP, a
  `person` decision, a hold in `.decree/attention/`), ntfy sends one message naming the
  machine, what happened, and the one command that continues it.
- One message per run per state: a run that stays failed doesn't repeat itself.
- It is on in a fresh install, with no setup beyond ntfy itself.
- The automation that reports failures can't report its own failure in a loop.

## Constraints

- No new service. It runs in the automation container.
- Monitoring add-ons (Grafana and the rest) are not required for it.

## Acceptance Criteria

- **Given** a machine whose script exits 1
  **When** it runs
  **Then** exactly one ntfy message names that machine and the retry command
- **Given** a run waiting in a `person` state
  **When** it starts waiting
  **Then** one ntfy message says it is waiting and how to answer
