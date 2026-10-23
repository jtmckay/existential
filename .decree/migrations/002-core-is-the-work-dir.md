---
machine: develop
---
# Core is "open the work dir, talk to an AI, have decree automate it"

## Overview

Core is what a new install should be. A user opens the work dir, starts a conversation with
an AI agent, and has decree automate things for them. Today Core is 18 services built around
hermes, a local ollama and Home Assistant, which most installs don't run on the same box. Files
(Nextcloud/Collabora), DNS (piHole), the house (Home Assistant) and GPU models run on other
servers.

## Outcome

- Core (`src/quests/00-core.md`) installs exactly: caddy, dashy, code-server, automation
  (decree and its webhook), ntfy, loki, prometheus, grafana, uptime-kuma, actual-budget.
- The numbered quests still partition Core exactly, one slice each:
  - network access (caddy, dashy)
  - workspace (code-server)
  - automation (automation, ntfy)
  - observability (loki, prometheus, grafana, uptime-kuma)
  - apps (actual-budget)
- Local AI (ollama, hermes, honcho, openviking, firecrawl), voice and home (Home Assistant,
  wyoming-whisper, wyoming-piper), Nextcloud, mealie and it-tools are still installable as
  unnumbered quests. Their guides keep the setup steps Core used to do for them.
- Core copies only what its own services need. It copies no ollama, Home Assistant, openviking
  or Nextcloud migrations or crons.
- Core's guide body describes the new Core: what you get, sizing (no GPU, no model pulls),
  and what to do after `docker compose up -d`.
- Everything that states what Core contains agrees with the quest: dashy's tiles, the tour
  page's service count and core/extra tiers, `footprint core`, and the docs that say "Core
  already did this".

## Constraints

- No service folder is deleted. Only Core's membership changes.
- `./existential.sh validate conventions` keeps enforcing the slice partition and the tour count.

## Acceptance Criteria

- **Given** a fresh checkout
  **When** `./existential.sh validate conventions` runs
  **Then** it exits 0
- **Given** Core's `services:` block
  **When** it is compared with the list in Outcome
  **Then** they contain the same ten services
- **Given** `./existential.sh run footprint core`
  **When** it runs
  **Then** it lists only those ten services' containers
