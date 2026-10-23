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
# redraw graph/ whenever a machine or cron file changes, so Obsidian shows the
# current graphs. Checked on the daemon's own tick; a machine decree cannot
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

# The daemon runs migrations itself, in order, each one waiting on the service
# it targets in its own wait_for_* state (automation/machines/*.yml).
exec decree daemon --no-color --interval 2s
