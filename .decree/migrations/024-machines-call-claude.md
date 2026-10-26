---
machine: develop
---
# Machines call Claude, and never change your notes

## Overview

Half of what decree is for is machines with AI in them, and that AI comes in at two places.
In a conversation (Claude or opencode in code-server's terminal) a person makes new machines.
In an automation, a machine calls AI itself while it runs. The stack allowed the second only as
a single answer from its own model endpoint: no AI CLI was installed in the `automation`
container, so a machine could never use the person's own Claude, and the machine that builds
machines wrote them with whatever chat model was there. Bringing your own Claude should reach
both places.

A machine's Claude runs with nobody to say yes, so it should act on its own. What keeps that
safe is what it can reach, not what it is told. Notes are a person's inputs, commands and
directions. A prompt injected through a note, an email or a web page must never be able to
change them, so the automation container sees them read-only. Machines stay writable there:
that is how an automation a person accepts gets built.

## Outcome

- The `automation` image ships Claude Code, pinned to a version, with its updater, telemetry and
  error reporting off.
- `automation/lib/ai.sh` is decree's `ai` helper exactly as `decree init` writes it for the
  pinned decree, plus only a `# shellcheck shell=bash` first line. A machine's script that
  wants Claude sources `automation/lib/agent.sh`:
  - `agent_ready` exits 0 when `claude` is installed and signed in;
  - `agent "<task>"` prints Claude's answer, run in the workspace, through `ai`, and fails with
    a message naming how to sign in when it is not signed in.
- Signing in is once per install: `docker exec -it automation claude`, then `/login`. The login
  lives in the container's home, the `decree_data` volume. As an alternative,
  `AUTOMATION_ANTHROPIC_API_KEY` or `AUTOMATION_CLAUDE_CODE_OAUTH_TOKEN` in
  `services/automation/.env` reach the container as `ANTHROPIC_API_KEY` and
  `CLAUDE_CODE_OAUTH_TOKEN`.
- A headless call runs with `CLAUDE_PERMISSION_MODE` from `AUTOMATION_CLAUDE_PERMISSION_MODE`,
  default `auto`: Claude acts on its own.
- No automation changes a note. In the `automation` container `workspace/notes/` is read-only,
  whatever runs and whatever Claude it calls. Machines that wrote into `notes/` write into
  `workspace/ai/` instead: the digest (`ai/you-were-here.md`, `ai/you-were-here/<YYYY>/`), the
  look backs beside it, and proposed automations (`ai/proposed/<name>.md`, accepted by moving
  them into `notes/automations/`).
- The workspace's `develop` writes an automation with Claude when `agent_ready`, and with the chat
  model when not. It tells the writer about `agent` only when Claude is signed in, and its gate
  refuses steps that call `agent` when it is not. A built automation's `steps` can call
  `agent` beside `ask`.
- The automation container's memory limit has room for a Claude call.
- CLAUDE.md, the decree reference, the workspace's decree skill notes and the Decree docs page
  say this: AI in the conversation and in the automations, and the two ways a machine reaches it
  (`model.sh`, `agent.sh`). Nothing in the repo says decree scripts never call an AI CLI.

## Constraints

- `automation/lib/ai.sh` is never edited; it is replaced with decree's own when decree is bumped.
- Nothing secret goes under `workspace/`: the login stays in `decree_data`, the keys in
  `services/automation/.env`.
- Without a Claude login, everything that worked before works the same: `develop` builds
  with the chat model, and no shipped machine needs `agent`.

## Acceptance Criteria

- **Given** a running stack
  **When** `docker exec automation touch /workspace/notes/x` runs
  **Then** it fails with a read-only file system
- **Given** the repo
  **When** `./existential.sh test decree` runs
  **Then** it fails if `automation/lib/ai.sh` differs from what the image's `decree init` writes
  (apart from the shellcheck line), and passes otherwise
- **Given** a rebuilt `automation` container
  **When** `docker exec automation claude --version` runs
  **Then** it prints the pinned version
- **Given** no login, no key and no token
  **When** a script calls `agent "x"`
  **Then** it exits non-zero and its stderr says `docker exec -it automation claude`
- **Given** Claude is signed in
  **When** `develop` builds an automation
  **Then** the build request goes to Claude rather than the chat model, and mentions `agent`
- **Given** Claude is not signed in
  **When** `develop` is given steps that call `agent`
  **Then** the gate fails, saying Claude is not signed in
