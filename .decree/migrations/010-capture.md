---
machine: develop
---
# Everything you put in lands in one capture stream

## Overview

What you asked an agent is the best record of what you were trying to do. It's the strongest
signal for "where was I?". Other inputs, like a phone shortcut, an ntfy reply or a voice memo
transcript, belong in the same place. Capture is the Input pillar made literal.

## Outcome

- `workspace/.capture/` holds the capture stream as JSON lines: timestamp, source, project or
  context where known, and text. It syncs with the rest of the workspace.
- Every prompt typed into Claude Code is captured, on by default, with no setup in
  code-server. On any other machine (a laptop, the host), one documented command enables the
  same capture.
- Every message typed into opencode in code-server is captured the same way.
- Only what the person typed is captured: never AI responses, tool output or transcripts.
- Before anything is written, obvious secrets are redacted: API keys and tokens of common
  shapes, `password=`/`token=` style assignments, and private key blocks. A redacted span
  is replaced by a marker that names the kind.
- `POST /capture` on automation-webhook appends the posted text with a source name, so a phone
  shortcut or any other tool can add to the stream.
- Turning capture off is one documented step for each source.

## Constraints

- Capture never blocks or slows the prompt. A failed capture is silent to the person and
  logged.
- Nothing outside `workspace/.capture/` is written by capture.

## Acceptance Criteria

- **Given** a prompt containing `sk-ant-...` and `password=hunter2`
  **When** it is submitted in code-server's Claude Code
  **Then** the captured line contains neither value, and does contain the rest of the prompt
- **Given** a Claude Code session that produced responses and tool output
  **When** `workspace/.capture/` is searched for that output
  **Then** none of it is found
- **Given** `POST /capture` with the webhook's token and `{"source":"phone","text":"buy filters"}`
  **When** it is sent
  **Then** a line with that source and text is appended
