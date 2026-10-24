---
machine: develop
---
# Core is "open the work dir, talk to an AI, have decree automate it": three services

## Overview

Core is what a new install should be, and nothing more: a user opens the work dir, starts a
conversation with an AI agent, and has decree automate things for them. Everything else is an
add-on, because most installs run files, DNS, the house and GPU models on other servers, and
every service in Core is one more thing a new user has to understand.

## Outcome

- Core (`src/quests/00-core.md`) installs exactly: code-server, automation (the decree
  daemon), ntfy, plus Tailscale on the host, which reaches them over real HTTPS (migration
  013), so Core has no reverse proxy. That is all the loop needs: write in code-server, ask Claude there, decree
  runs it, ntfy tells you.
- automation-webhook is an add-on with its own flag, and on-demand endpoints (`/capture`,
  `/you-were-here`, `/look-back`) come with it. Everything it triggers can also be started from
  code-server's terminal.
- The numbered quests still partition Core exactly, one slice each:
  - access (Tailscale on the host; no container, so the slice names it in its guide)
  - workspace (code-server)
  - automation (automation, ntfy)
- Add-ons, each an unnumbered quest whose guide keeps the setup steps Core used to do for it:
  - network: caddy, for `https://<slug>.<domain>` hostnames, LAN access without Tailscale, or
    many web add-ons
  - monitoring: dashy, loki, prometheus, grafana, uptime-kuma
  - capture: automation-webhook, Nextcloud (the prime example of capture from a phone)
  - apps: actual-budget, mealie, it-tools
  - local AI (ollama, hermes, honcho, openviking, firecrawl), voice and home (Home Assistant,
    wyoming-whisper, wyoming-piper)
- Backups are outside Core. Core's guide suggests putting the workspace under git, with a
  remote the user chooses, as the simplest way to keep it safe.
- Core copies only what its own services need. It copies no ollama, Home Assistant, openviking
  or Nextcloud migrations or crons.
- Core's guide body describes the new Core: what you get, sizing (no GPU, no model pulls),
  and what to do after `docker compose up -d`.
- Everything that states what Core contains agrees with the quest: the tour page's service
  count and core/extra tiers, `footprint core`, README's and intro's "What Core installs", and
  the docs that say "Core already did this". After `docker compose up -d`, the guide sends the
  user to code-server, not a dashboard.

## Constraints

- No service folder is deleted. Giving automation-webhook its own flag may move it into its
  own folder; nothing else moves.
- `./existential.sh validate conventions` keeps enforcing the slice partition and the tour count.

## Acceptance Criteria

- **Given** a fresh checkout
  **When** `./existential.sh validate conventions` runs
  **Then** it exits 0
- **Given** Core's `services:` block
  **When** it is compared with the list in Outcome
  **Then** they contain the same three services
- **Given** `./existential.sh run footprint core`
  **When** it runs
  **Then** it lists only those three services' containers, with no automation-webhook
