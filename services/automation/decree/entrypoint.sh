#!/usr/bin/env bash
set -euo pipefail

# EXIST_PUID/PGID is only known at container start, not at build — /etc/passwd
# ships with no entry for it, and OpenSSH's getpwuid() refuses to run at all
# ("No user exists for uid N") without one, breaking notes_pull's ssh/rsync
# path. The Dockerfile makes /etc/passwd world-writable for exactly this.
if ! getent passwd "$(id -u)" >/dev/null 2>&1; then
  echo "decree:x:$(id -u):$(id -g):decree:${HOME:-/home/decree}:/bin/bash" >> /etc/passwd
fi

# A one-off command (`docker run existential/decree:local decree check`).
if [[ $# -gt 0 ]]; then
  exec "$@"
fi

# FILE_HANDLERS=1 (the `automation` daemon): a change to a workspace file starts
# the machine of every handler in .decree/handlers.yml that matches it
# (automation/lib/file-handlers.ts). It re-reads handlers.yml itself; this loop
# only brings it back if it dies. Plain node, which strips the types itself:
# it never exits, and tsx would hold a second node and esbuild beside it.
if [[ "${FILE_HANDLERS:-}" == 1 ]]; then
  ( while :; do node .decree/lib/file-handlers.ts || true; sleep 5; done ) &
fi

# ATTENTION_NOTIFY=1 (the `automation` daemon): each run that fails or waits on a
# person becomes one ntfy message (automation/lib/attention-notify.sh). It runs
# beside the daemon, not as a decree run, so its own failure leaves nothing to report.
if [[ "${ATTENTION_NOTIFY:-}" == 1 ]]; then
  ( while :; do bash .decree/lib/attention-notify.sh || true; sleep 5; done ) &
fi

# This project's skill for Claude, at the workspace root (automation/lib/skill-notes.md):
# how a machine made here is offered, not installed. decree's own is beside it,
# written by the skill plugin (decree_skill) at each daemon start.
if [[ "${FILE_HANDLERS:-}" == 1 && -d /workspace/.decree ]]; then
  mkdir -p /workspace/.claude/skills/existential
  cp .decree/lib/skill-notes.md /workspace/.claude/skills/existential/SKILL.md || echo "[entrypoint] existential skill not written" >&2
fi

# pi's provider and MCP servers (lib/pi.sh), rewritten every boot so a
# changed chat endpoint or a disabled add-on follows. Only where a chat model is
# named: automation-backup runs no agent.
if [[ -n "${EXIST_MODEL_CHAT:-}" && -f .decree/lib/pi.sh ]]; then
  ( . .decree/lib/pi.sh && pi_configure ) || echo "[entrypoint] pi not configured" >&2
fi

# The daemon runs each machine's order files at start (decree's `decree_order` plugin),
# in order, each one waiting on the service it targets in its own wait_for_*
# state (automation/plugins/*.md). Its plugins are installed by the host: here
# machines/ and plugins/ are read-only.
exec decree daemon --no-color --interval 2s
