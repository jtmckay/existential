#!/usr/bin/env bash
# exist.test.sh — validate that ntfy is reachable and accepts authenticated
# publishes. Publishing to a one-off topic is non-destructive (ntfy purges
# unsubscribed topics; we don't subscribe).
#
# See CLAUDE.md "Service test scripts" for the convention.

set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../src/test" && pwd)/exist-test.sh"
exist_self_elevate
exist_test_init "ntfy" EXIST_IS_SERVICES_NTFY
skip_if_disabled

load_env_exist

NTFY_URL="${NTFY_URL:-${EXIST_NTFY_URL:-http://ntfy:80}}"
NTFY_TOKEN="${NTFY_TOKEN:-${EXIST_NTFY_TOKEN:-}}"

# ── 1. Health ────────────────────────────────────────────────────────────────

HEALTH=$(curl -sS --max-time 5 "${NTFY_URL}/v1/health" 2>/dev/null || true)
if [ -z "$HEALTH" ]; then
    fail "ntfy /v1/health reachable" \
         "no response from ${NTFY_URL}/v1/health" \
         "docker ps | grep ntfy; docker logs ntfy"
elif printf '%s' "$HEALTH" | grep -q '"healthy"'; then
    ok "ntfy /v1/health reachable"
else
    fail "ntfy /v1/health reachable" \
         "unexpected payload: ${HEALTH}" \
         "docker logs ntfy"
fi

# Routing coverage — same /v1/health reached via caddy. Separates "ntfy down"
# from "caddy/pihole routing broken".
probe_caddy "ntfy /v1/health" ntfy /v1/health 200

# ── 2. Authenticated publish ─────────────────────────────────────────────────

if [ -z "$NTFY_TOKEN" ]; then
    warn "ntfy authenticated publish" \
         "no NTFY_TOKEN / EXIST_NTFY_TOKEN set — auth not verified" \
         "Run ./existential.sh run ntfy to mint and save a bot token"
else
    CODE=$(curl -sS -o /dev/null -w "%{http_code}" --max-time 5 \
        -H "Authorization: Bearer ${NTFY_TOKEN}" \
        -H "Title: Existential Test" \
        -d "exist.test.sh ping $(date +%s)" \
        "${NTFY_URL}/exist-test" 2>/dev/null || echo "000")
    case "$CODE" in
        200) ok "ntfy authenticated publish (topic=exist-test)" ;;
        401|403) fail "ntfy authenticated publish" \
                       "HTTP $CODE — token rejected" \
                       "Token may be expired or revoked. Re-run ./existential.sh run ntfy" ;;
        000) fail "ntfy authenticated publish" \
                  "no response" \
                  "docker logs ntfy" ;;
        *)   fail "ntfy authenticated publish" \
                  "HTTP $CODE" \
                  "docker logs ntfy" ;;
    esac
fi

finish
