#!/usr/bin/env bash
# Tests that rclone remotes are configured and each one is reachable.

set -euo pipefail

RCLONE_CONFIG="${SECRETS_DIR:-/secrets}/rclone/rclone.conf"

if [ ! -f "$RCLONE_CONFIG" ]; then
    echo "No rclone config at ${RCLONE_CONFIG} — run: ./existential.sh setup rclone" >&2
    exit 1
fi

mapfile -t remotes < <(rclone --config "$RCLONE_CONFIG" listremotes 2>/dev/null | sed 's/:$//')

if [ ${#remotes[@]} -eq 0 ]; then
    echo "No remotes configured in ${RCLONE_CONFIG}" >&2
    exit 1
fi

FAIL=0
for remote in "${remotes[@]}"; do
    if rclone --config "$RCLONE_CONFIG" lsd "${remote}:" --max-depth 1 >/dev/null 2>&1; then
        echo "  OK: ${remote}"
    else
        echo "  FAIL: ${remote} (unreachable)"
        ((FAIL++))
    fi
done

if [ "$FAIL" -gt 0 ]; then
    echo "$FAIL remote(s) unreachable" >&2
    exit 1
fi

echo "rclone: all ${#remotes[@]} remote(s) reachable"
