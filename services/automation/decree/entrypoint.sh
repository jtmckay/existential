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

# GRAPH_WATCH=1 (the `automation` daemon, whose project is workspace/.decree):
# redraw graph/ whenever a machine or cron file changes, so the graphs in the
# workspace are always current. Checked on the daemon's own tick; a machine decree cannot
# parse is reported once and redrawn when it next changes.
if [[ "${GRAPH_WATCH:-}" == 1 ]]; then
  (
    last=""
    while :; do
      now="$({ cat .decree/machines/*.yml .decree/cron/*.md 2>/dev/null || true; } | cksum)"
      if [[ "$now" != "$last" ]]; then
        decree graph --no-color >/dev/null || echo "[entrypoint] decree graph failed" >&2
        last="$now"
      fi
      sleep 2
    done
  ) &
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

# The decree skill for Claude, at the workspace root, so `claude` started in
# /workspace (code-server's terminal) already knows how to write a machine.
# This project's notes (automation/lib/skill-notes.md) are appended to SKILL.md.
# Rewritten only when the image's decree version or the notes change: `decree
# skill` overwrites its own files and leaves anything else in that folder alone.
if [[ "${GRAPH_WATCH:-}" == 1 && -d /workspace/.decree ]]; then
  stamp=/data/.decree-skill-version
  version="$(decree --version) $(cksum < .decree/lib/skill-notes.md)"
  if [[ ! -f /workspace/.claude/skills/decree/SKILL.md || "$(cat "$stamp" 2>/dev/null)" != "$version" ]]; then
    if (cd /workspace && decree skill --ai claude --no-color >/dev/null); then
      cat .decree/lib/skill-notes.md >> /workspace/.claude/skills/decree/SKILL.md
      echo "$version" > "$stamp"
    else
      echo "[entrypoint] decree skill failed" >&2
    fi
  fi
fi

# The daemon runs migrations itself, in order, each one waiting on the service
# it targets in its own wait_for_* state (automation/machines/*.yml).
exec decree daemon --no-color --interval 2s
