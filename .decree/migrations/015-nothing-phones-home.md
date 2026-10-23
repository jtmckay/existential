---
machine: develop
---
# Existential collects nothing and phones nothing home

## Overview

The pitch says Existential makes no money from you and collects nothing. That has to be true
of the stack as shipped, not just of the repo's own code: several upstream services send
usage statistics or telemetry by default.

## Outcome

- Every service a Core install runs ships with its telemetry, usage reporting and analytics
  turned off, wherever the upstream project offers a setting for it. Known defaults to check
  include Grafana (usage stats), Loki (usage reporting), code-server, and Claude Code and
  opencode in code-server's terminal; the rest of Core is checked too, not assumed clean.
- Update checks that only download a version number may stay. Anything that sends usage,
  identifiers or content goes.
- Add-on services follow the same rule when they are enabled.
- Where an upstream service has no way to turn reporting off, its docs page says so in one
  line.
- The docs say plainly, where the default domain is explained, that a nip.io domain sends
  every hostname lookup to nip.io's public DNS, which reveals the host's IP and the service
  names looked up, and that local DNS (such as a piHole) or a domain you own avoids it.
- The rule is recorded in `.claude/reference/services.md`, so a new service ships the same way.
- An AI provider the user configures is their choice and under their terms; nothing here
  changes it.

## Constraints

- No new service, proxy or firewall rule. Use each upstream project's own setting.

## Acceptance Criteria

- **Given** a Core install's rendered config
  **When** each service's telemetry setting is read
  **Then** every one that has a setting has it off
- **Given** a new service added later
  **When** `.claude/reference/services.md` is read
  **Then** it says telemetry ships off
