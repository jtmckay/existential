#!/usr/bin/env bash
# exist.test.sh — validate that the homeassistant container is running and
# reachable.
#
# HA's /api/ returns {"message":"API running."} only for an authenticated
# caller. A long-lived access token is minted by hand in the HA UI and the
# stack configures none, so asserting that payload made this test unpassable on
# every install. What is verifiable without a token: the frontend serves
# /manifest.json, and /api/ answers 401 — which proves the API layer is up and
# enforcing auth, not that it is down.
#
# See .claude/reference/testing.md for the convention.

set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../src/test" && pwd)/exist-test.sh"
exist_self_elevate
exist_test_init "homeassistant" EXIST_IS_SERVICES_HOMEASSISTANT
skip_if_disabled

load_env_exist

HA_URL="${HA_URL:-http://homeassistant:8123}"

# ── 1. Health ────────────────────────────────────────────────────────────────

# Frontend liveness — unauthenticated, so this works on any install.
http_probe "homeassistant /manifest.json" "${HA_URL}/manifest.json"

# API layer. 200 means a token is configured and valid; 401 means the API is up
# and refusing an anonymous caller — both prove the service is serving. Anything
# else (000, 502, 404) is a real failure.
API_CODE=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 5 "${HA_URL}/api/" 2>/dev/null || echo "000")
case "$API_CODE" in
    200) ok "homeassistant /api/ (authenticated)" ;;
    401) ok "homeassistant /api/ (up, auth enforced)" ;;
    000) fail "homeassistant /api/ reachable" \
              "no response from ${HA_URL}/api/" \
              "docker ps | grep homeassistant; docker logs homeassistant" ;;
    *)   fail "homeassistant /api/ reachable" \
              "HTTP ${API_CODE}" \
              "docker logs homeassistant" ;;
esac

# Routing coverage — reached via Caddy. Separates "HA down" from "caddy/pihole
# routing broken". Uses the unauthenticated endpoint so the expected status does
# not depend on whether a token happens to be configured.
probe_caddy "homeassistant /manifest.json" homeassistant /manifest.json 200

finish
