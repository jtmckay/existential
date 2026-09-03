#!/usr/bin/env bash
# exist.test.sh — validate that ntfy is reachable and accepts authenticated
# publishes. Publishing to a one-off topic is non-destructive (ntfy purges
# unsubscribed topics; we don't subscribe).
#
# See .claude/reference/testing.md for the convention.

set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../src/test" && pwd)/exist-test.sh"
exist_self_elevate
exist_test_init "ntfy" EXIST_IS_SERVICES_NTFY
skip_if_disabled

load_env_exist

NTFY_URL="${NTFY_URL:-${EXIST_NTFY_URL:-http://ntfy:80}}"
NTFY_TOKEN="${NTFY_TOKEN:-${EXIST_NTFY_TOKEN:-}}"
# The bot user ntfy's entrypoint creates on first boot. A token is the opt-in
# alternative and wins when both are set — same precedence as notify.sh.
NTFY_USER="${NTFY_USER:-${EXIST_NTFY_USER:-}}"
NTFY_PASSWORD="${NTFY_PASSWORD:-${EXIST_NTFY_PASSWORD:-}}"

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

# ── 2. Auth is actually enforced ─────────────────────────────────────────────

# server.exist.yml sets auth-default-access: deny-all — the whole reason this
# service needs no manual step, per site/docs/services/ntfy.md, is that a
# fresh install would otherwise accept every publish from anyone. A publish
# with NO credentials at all must be rejected (verified against a real
# v2.27.0 container: 403, not 401); a 200 here means that setting was lost
# (server.yml not mounted, or reverted upstream) and the instance is silently
# open to the internet if it's exposed through Caddy.
NOAUTH_CODE=$(curl -sS -o /dev/null -w "%{http_code}" --max-time 5 \
    -d "exist.test.sh unauthenticated ping $(date +%s)" \
    "${NTFY_URL}/exist-test-noauth" 2>/dev/null || echo "000")
case "$NOAUTH_CODE" in
    401 | 403) ok "ntfy rejects unauthenticated publish (deny-all enforced)" ;;
    200) fail "ntfy rejects unauthenticated publish" \
              "HTTP 200 — an unauthenticated publish succeeded, deny-all is NOT enforced" \
              "docker exec ntfy cat /etc/ntfy/server.yml | grep auth-default-access; confirm ntfy-config/server.yml is mounted" ;;
    000) fail "ntfy rejects unauthenticated publish" \
              "no response" \
              "docker logs ntfy" ;;
    *)   fail "ntfy rejects unauthenticated publish" \
              "unexpected HTTP $NOAUTH_CODE" \
              "docker logs ntfy" ;;
esac

# ── 3. Authenticated publish ─────────────────────────────────────────────────

AUTH_ARGS=()
AUTH_KIND=""
if [ -n "$NTFY_TOKEN" ]; then
    AUTH_ARGS=(-H "Authorization: Bearer ${NTFY_TOKEN}")
    AUTH_KIND="token"
elif [ -n "$NTFY_USER" ] && [ -n "$NTFY_PASSWORD" ]; then
    AUTH_ARGS=(-u "${NTFY_USER}:${NTFY_PASSWORD}")
    AUTH_KIND="user ${NTFY_USER}"
fi

if [ -z "$AUTH_KIND" ]; then
    warn "ntfy authenticated publish" \
         "no credential set — auth not verified" \
         "EXIST_NTFY_USER/EXIST_NTFY_PASSWORD are set in .env.shared by default; check they survived"
else
    CODE=$(curl -sS -o /dev/null -w "%{http_code}" --max-time 5 \
        "${AUTH_ARGS[@]}" \
        -H "Title: Existential Test" \
        -d "exist.test.sh ping $(date +%s)" \
        "${NTFY_URL}/exist-test" 2>/dev/null || echo "000")
    case "$CODE" in
        200) ok "ntfy authenticated publish (topic=exist-test, ${AUTH_KIND})" ;;
        401|403) fail "ntfy authenticated publish" \
                       "HTTP $CODE — credential rejected (${AUTH_KIND})" \
                       "docker logs ntfy | grep -i user; the bot is created by ntfy's entrypoint on first boot" ;;
        000) fail "ntfy authenticated publish" \
                  "no response" \
                  "docker logs ntfy" ;;
        *)   fail "ntfy authenticated publish" \
                  "HTTP $CODE" \
                  "docker logs ntfy" ;;
    esac
fi

finish
