---
machine: develop
---
# Claude Code and opencode are ready in code-server, reachable remotely

## Overview

Starting an AI conversation in the work dir should take no setup. The user also wants to keep
that conversation going from a phone.

## Outcome

- code-server's terminal has `claude` (Claude Code) and `opencode` on PATH on first boot. Their
  installs and logins survive container recreation.
- opencode is configured to use the stack's OpenAI-compatible model endpoint, with nothing
  for the user to set beyond that endpoint.
- code-server ships with a markdown preview that renders mermaid, so every machine's graph in
  `.decree/graph/` shows as a diagram. That is how the user sees the flows they've set up.
  The extension comes from Open VSX and survives container recreation.
- The terminal has `tmux` and the repo's `tmx` function (`.claude/reference/services.md`).
  `tmx -d claude claude remote-control` starts a remote-control session, re-attachable with
  `tmx claude`, and never starts a second copy while one is running.
- The code-server docs page says, in a sentence or two, where conversations go: to whichever
  AI provider the user configures, under that provider's terms. Existential itself sends and
  collects nothing. A model on your own hardware is the private option, a hosted one the easy
  option.
- The repo's rules say that code-server ships these CLIs for a person to drive, and that
  decree scripts never call an AI CLI.

## Constraints

- No other container installs an AI CLI.
- code-server's memory limit still follows the convention (sized for a real editing session).

## Acceptance Criteria

- **Given** a freshly recreated code-server container
  **When** `docker exec code-server bash -lc 'claude --version && opencode --version && tmux -V'` runs
  **Then** it exits 0
- **Given** a freshly recreated code-server container
  **When** its installed extensions are listed
  **Then** a mermaid-rendering markdown preview is among them
- **Given** a running `claude` tmux session
  **When** `tmx -d claude claude remote-control` runs again
  **Then** `tmux ls` still shows exactly one `claude` session
