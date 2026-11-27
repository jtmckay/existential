---
machine: repo_develop
---
# AI in two places: a conversation in code-server, and machines that call it themselves

## Overview

Half of what decree is for is machines with AI in them. In a conversation (Claude, opencode or
pi in code-server's terminal) a person makes new machines; in an automation, a machine calls
AI itself while it runs. Starting a conversation should take no setup, it should be
continuable from a phone, and bringing your own Claude should reach both places. A machine's
Claude runs with nobody to say yes; what keeps that safe is what it can reach, not what it is
told.

## Outcome

- **code-server's terminal** has `claude`, `opencode` and `pi` on PATH on first boot; installs
  and logins survive container recreation. opencode and pi use the stack's model address
  (`04-models.md`) with nothing else to set.
- code-server ships a markdown preview that renders mermaid (from Open VSX, surviving
  recreation), so every machine's `graph.md` shows as a diagram.
- The terminal has `tmux` and the repo's `tmx` function: `tmx -d claude claude remote-control`
  starts a remote-control session, re-attachable with `tmx claude`, never a second copy.
- **Three ways a machine calls AI**, each a library plugin it `needs:`:
  - `model` (`lib/model.sh`: `model_chat`, `model_gate`): one answer from the model address.
  - `pi` (`lib/pi.sh`: `pi_run`): pi with tools on the same model, in a department
    (`store/agent_task/departments/<name>.yml`, a file that picks its tools and MCP servers).
  - `agent` (`lib/agent.sh`): Claude Code with tools, through `ai` from decree's official
    `decree_ai`. `agent_ready` exits 0 when `claude` is installed and signed in; `agent
    "<task>"` prints Claude's answer, and fails naming how to sign in when it is not.
- The `automation` image ships Claude Code, pinned, with its updater, telemetry and error
  reporting off. Signing in is once per install, in code-server's terminal (`claude`, then
  `/login`): automation shares that login (its `CLAUDE_CONFIG_DIR` is code-server's).
  `AUTOMATION_ANTHROPIC_API_KEY` or `AUTOMATION_CLAUDE_CODE_OAUTH_TOKEN` in
  `services/automation/.env` are the alternative.
- A headless call runs in `AUTOMATION_CLAUDE_PERMISSION_MODE`, default `auto`, kept from notes
  by the read-only mount (`workspace.md`).
- The code-server docs page says where conversations go: to the AI provider the person
  configures, under that provider's terms. Existential itself sends and collects nothing.
- Repo-editing belongs to a coding agent on the host, against a frontier model; the stack's
  own agents work on the workspace.

## Constraints

- decree's `decree_ai` is never edited: a change to it is a plugin that `extends:` it.
- Nothing secret goes under `workspace/`.
- Without a Claude login everything works the same, on the chat model; no default plugin needs
  `agent`.

## Acceptance Criteria

- **Given** a freshly recreated code-server container
  **When** `docker exec code-server bash -lc 'claude --version && opencode --version && tmux -V'` runs
  **Then** it exits 0
- **Given** a running `claude` tmux session
  **When** `tmx -d claude claude remote-control` runs again
  **Then** `tmux ls` still shows exactly one `claude` session
- **Given** no login, no key and no token
  **When** a script calls `agent "x"`
  **Then** it exits non-zero and says to sign in from code-server's terminal
- **Given** `./existential.sh test code-server-agents`
  **Then** it exits 0
