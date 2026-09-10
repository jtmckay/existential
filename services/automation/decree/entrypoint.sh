#!/usr/bin/env bash
set -euo pipefail

# EXIST_PUID/PGID is only known at container start, not at build — /etc/passwd
# ships with no entry for it, and OpenSSH's getpwuid() refuses to run at all
# ("No user exists for uid N") without one, breaking notes-pull's ssh/rsync
# path. The Dockerfile makes /etc/passwd world-writable for exactly this.
if ! getent passwd "$(id -u)" >/dev/null 2>&1; then
  echo "decree:x:$(id -u):$(id -g):decree:${HOME:-/home/decree}:/bin/bash" >> /etc/passwd
fi

# Default DECREE_CONTAINER to hostname (Docker sets this to 12-char container ID)
DECREE_CONTAINER="${DECREE_CONTAINER:-$HOSTNAME}"
export DECREE_CONTAINER

if [[ -z "$DECREE_CONTAINER" ]]; then
  echo "ERROR: DECREE_CONTAINER must not be empty" >&2; exit 1
fi
if [[ "$DECREE_CONTAINER" == *"__"* ]]; then
  echo "ERROR: DECREE_CONTAINER must not contain '__': $DECREE_CONTAINER" >&2; exit 1
fi
if ! [[ "$DECREE_CONTAINER" =~ ^[a-zA-Z0-9_-]+$ ]]; then
  echo "ERROR: DECREE_CONTAINER contains invalid characters (only [a-zA-Z0-9_-] allowed): $DECREE_CONTAINER" >&2; exit 1
fi

# Install AI tool if requested
DECREE_AI="${DECREE_AI:-}"
if [[ -n "$DECREE_AI" ]]; then
  case "$DECREE_AI" in
    opencode)
      if ! command -v opencode &>/dev/null; then
        echo "Installing opencode-ai..."
        npm i -g opencode-ai
      fi
      ;;
    claude)
      if ! command -v claude &>/dev/null; then
        echo "Installing claude-code..."
        npm i -g @anthropic-ai/claude-code
      fi
      ;;
    *)
      echo "WARNING: Unknown DECREE_AI value: $DECREE_AI (supported: opencode, claude)" >&2
      ;;
  esac
fi

# Initialize decree if .decree/ doesn't exist
if [[ ! -d /work/.decree ]]; then
  decree init --no-color </dev/null
fi

# If CMD arguments were passed, exec them directly
if [[ $# -gt 0 ]]; then
  exec "$@"
fi

DECREE_DAEMON="${DECREE_DAEMON:-true}"

# ── Daemon startup: wait for service health, then run migrations ──────────────
#
# When DECREE_DAEMON=true and exist.test.sh is mounted at /work/exist.test.sh,
# the daemon waits for that script to pass before running `decree process`
# (migrations). This ensures migrations never run against a service that is
# still starting up. For `decree` the script is migration-gate.sh, which probes
# every service the daemon's migrations target.
#
# The test script is mounted at /work/exist.test.sh (not inside /work/.decree/)
# to avoid overlapping with the decree state-dir bind mount.
#
# The loop retries for up to DECREE_MIGRATE_TIMEOUT seconds (default 300).
# If the timeout is reached the daemon starts anyway but SKIPS migrations —
# deferring a migration is recoverable, running it against a service that is not
# ready is not, and blocking forever is not either.

if [[ "$DECREE_DAEMON" == "true" && -f "/work/exist.test.sh" ]]; then
  _timeout="${DECREE_MIGRATE_TIMEOUT:-300}"
  _interval=10
  _elapsed=0

  # True unless the timeout branch below fires. This flag is what makes the
  # timeout mean what its message says: `break` alone left the loop and fell
  # straight into `decree process`, so the log read "starting daemon without
  # migrations" and the very next line ran them — firing every migration at
  # services the gate had just proved were not ready. `decree process` halts at
  # the first dead letter, so one slow service took down every migration queued
  # behind it too.
  _gate_passed=true

  echo "[decree] Waiting for service health check to pass..."
  until bash /work/exist.test.sh >/dev/null 2>&1; do
    _elapsed=$((_elapsed + _interval))
    if [[ $_elapsed -ge $_timeout ]]; then
      _gate_passed=false
      echo "[decree] Health check timed out after ${_timeout}s — starting daemon WITHOUT running migrations." >&2
      echo "[decree] Pending migrations stay pending; nothing is lost. Fix the unhealthy" >&2
      echo "[decree] service, then run: docker exec ${DECREE_CONTAINER} decree process" >&2
      break
    fi
    echo "[decree] Not yet healthy, retrying in ${_interval}s (${_elapsed}/${_timeout}s)..."
    sleep "$_interval"
  done

  if [[ "$_gate_passed" == "true" ]]; then
    echo "[decree] Running migrations..."
    decree process --no-color 2>&1 || echo "[decree] WARNING: some migrations failed — check logs" >&2
  fi
fi

# ── Start daemon or interactive shell ─────────────────────────────────────────

if [[ "$DECREE_DAEMON" == "true" ]]; then
  exec decree daemon --no-color --interval "${DECREE_INTERVAL:-2}"
else
  exec bash
fi
