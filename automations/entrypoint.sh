#!/usr/bin/env bash
set -euo pipefail

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
    copilot)
      if ! command -v gh &>/dev/null; then
        echo "Installing GitHub CLI..."
        ARCH=$(dpkg --print-architecture)
        GH_VERSION=$(curl -fsSL https://api.github.com/repos/cli/cli/releases/latest \
          | sed -n 's/.*"tag_name": "v\([^"]*\)".*/\1/p')
        curl -fsSL "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_${ARCH}.deb" \
          -o /tmp/gh.deb
        dpkg -i /tmp/gh.deb && rm /tmp/gh.deb
      fi
      if ! gh extension list 2>/dev/null | grep -q copilot; then
        echo "Installing GitHub Copilot extension..."
        gh extension install github/gh-copilot
      fi
      ;;
    *)
      echo "WARNING: Unknown DECREE_AI value: $DECREE_AI (supported: opencode, claude, copilot)" >&2
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

# ── Sidecar startup: wait for service health, then run migrations ─────────────
#
# When DECREE_SIDECAR=true and exist.test.sh is mounted at /work/exist.test.sh,
# the sidecar waits for the service to pass its health check before running
# `decree process` (migrations). This ensures migrations never run against a
# service that is still starting up.
#
# The test script is mounted at /work/exist.test.sh (not inside /work/.decree/)
# to avoid overlapping with the decree state-dir bind mount.
#
# The loop retries for up to DECREE_MIGRATE_TIMEOUT seconds (default 300).
# If the timeout is reached, the sidecar logs a warning and starts the daemon
# anyway — missing a migration on first boot is recoverable; blocking forever
# is not.

if [[ "$DECREE_DAEMON" == "true" && -f "/work/exist.test.sh" ]]; then
  _timeout="${DECREE_MIGRATE_TIMEOUT:-300}"
  _interval=10
  _elapsed=0

  echo "[decree] Waiting for service health check to pass..."
  until bash /work/exist.test.sh >/dev/null 2>&1; do
    _elapsed=$((_elapsed + _interval))
    if [[ $_elapsed -ge $_timeout ]]; then
      echo "[decree] Health check timed out after ${_timeout}s — starting daemon without migrations" >&2
      break
    fi
    echo "[decree] Not yet healthy, retrying in ${_interval}s (${_elapsed}/${_timeout}s)..."
    sleep "$_interval"
  done

  echo "[decree] Running migrations..."
  decree process --no-color 2>&1 || echo "[decree] WARNING: some migrations failed — check logs" >&2
fi

# ── Start daemon or interactive shell ─────────────────────────────────────────

if [[ "$DECREE_DAEMON" == "true" ]]; then
  exec decree daemon --no-color --interval "${DECREE_INTERVAL:-2}"
else
  exec bash
fi
