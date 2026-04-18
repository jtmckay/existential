#!/usr/bin/env bash
# Tests that the ntfy service is reachable and accepts authenticated publishes.

set -euo pipefail

NTFY_URL="${NTFY_URL:-http://localhost:44680}"
NTFY_TOKEN="${NTFY_TOKEN:-}"

# Try loading token from root .env if not set
if [ -z "$NTFY_TOKEN" ]; then
    ROOT_ENV="${REPO_ROOT:-.}/.env"
    if [ -f "$ROOT_ENV" ]; then
        # shellcheck source=/dev/null
        source "$ROOT_ENV"
        NTFY_TOKEN="${NTFY_TOKEN:-}"
    fi
fi

# Health check
HEALTH=$(curl -sf "${NTFY_URL}/v1/health" 2>&1) || {
    echo "ntfy unreachable at ${NTFY_URL}" >&2
    exit 1
}

printf '%s' "$HEALTH" | grep -q '"healthy"' || {
    echo "ntfy health check failed: ${HEALTH}" >&2
    exit 1
}

# Publish test (requires token)
if [ -z "$NTFY_TOKEN" ]; then
    echo "ntfy: reachable (skipping publish — no NTFY_TOKEN)"
    exit 0
fi

HTTP_STATUS=$(curl -sf -o /dev/null -w "%{http_code}" \
    -H "Authorization: Bearer ${NTFY_TOKEN}" \
    -H "Title: Existential Test" \
    -d "Integration test $(date +%s)" \
    "${NTFY_URL}/exist-test") || {
    echo "ntfy publish request failed" >&2
    exit 1
}

[ "$HTTP_STATUS" = "200" ] || {
    echo "ntfy publish returned HTTP ${HTTP_STATUS}" >&2
    exit 1
}

echo "ntfy: reachable and publish OK"
