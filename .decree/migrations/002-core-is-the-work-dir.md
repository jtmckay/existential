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

- Core is what `.env.exist.shared` ships on, exactly: code-server, automation (the decree
  daemon), ntfy, plus Tailscale on the host, which reaches them over real HTTPS (migration
  013), so Core has no reverse proxy. That is all the loop needs: write in code-server, ask
  Claude there, decree runs it, ntfy tells you.
- automation-webhook is an add-on with its own flag, and on-demand endpoints (`/capture`,
  `/you-were-here`, `/look-back`) come with it. Everything it triggers can also be started from
  code-server's terminal.
- Everything past Core is an add-on: a flow that turns on what it needs (migration 023), or one
  `EXIST_IS_*` flag, with any manual setup on that service's docs page: Caddy (hostnames, LAN
  access without Tailscale, its CA), monitoring (dashy, loki, prometheus, grafana,
  uptime-kuma), Nextcloud and the webhook, the apps, local AI, voice and home.
- Backups are outside Core. Getting Started suggests putting the workspace under git, with a
  remote the user chooses, as the simplest way to keep it safe.
- The default flows (on in every install) need nothing beyond Core's services: no ollama, Home
  Assistant, openviking or Nextcloud migrations or crons.
- Everything that states what Core contains agrees with `.env.exist.shared`: the tour page's
  "With Core" flows (each runs on Core's services, plus a chat model where it says so),
  `footprint core`, README's and intro's "What Core installs", and the docs that say "Core
  already did this". After `docker compose up -d`, Getting Started sends the user to
  code-server, not a dashboard.

## Constraints

- No service folder is deleted. Giving automation-webhook its own flag may move it into its
  own folder; nothing else moves.

## Acceptance Criteria

- **Given** a fresh checkout
  **When** `./existential.sh validate conventions` runs
  **Then** it exits 0
- **Given** the `EXIST_IS_*=true` lines in `.env.exist.shared`
  **When** they are compared with the list in Outcome
  **Then** they contain the same three services
- **Given** `./existential.sh run footprint core`
  **When** it runs
  **Then** it lists only those three services' containers, with no automation-webhook
