#!/usr/bin/env bash
# exist.test.sh — validate that the homeassistant container is running and
# reachable. HA's /api/ endpoint returns {"message":"API running."} when healthy.
#
# See CLAUDE.md "Service test scripts" for the convention.

set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../src/test" && pwd)/exist-test.sh"
exist_self_elevate
exist_test_init "homeassistant" EXIST_IS_SERVICES_HOMEASSISTANT
skip_if_disabled

load_env_exist

HA_URL="${HA_URL:-http://homeassistant:8123}"

# ── 1. Health ────────────────────────────────────────────────────────────────

HEALTH=$(curl -sS --max-time 5 "${HA_URL}/api/" 2>/dev/null || true)
if [ -z "$HEALTH" ]; then
    fail "homeassistant /api/ reachable" \
         "no response from ${HA_URL}/api/" \
         "docker ps | grep homeassistant; docker logs homeassistant"
elif printf '%s' "$HEALTH" | grep -q '"message"'; then
    ok "homeassistant /api/ reachable"
else
    fail "homeassistant /api/ reachable" \
         "unexpected payload: ${HEALTH}" \
         "docker logs homeassistant"
fi

# Routing coverage — same endpoint reached via Caddy. Separates "HA down"
# from "caddy/pihole routing broken".
probe_caddy "homeassistant /api/" homeassistant /api/ 200

finish
