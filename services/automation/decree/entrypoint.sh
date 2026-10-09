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

# The daemon runs migrations itself, in order, each one waiting on the service
# it targets in its own wait_for_* state (automation/machines/*.yml).
exec decree daemon --no-color --interval 2s
