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
# not depend on whether a token happens to be configured. Caddy's reverse_proxy
# adds X-Forwarded-For itself, so a 400 through this path (HA up, direct :8123
# fine) almost always means the check below would also fail.
probe_caddy "homeassistant /manifest.json" homeassistant /manifest.json 200

# ── 2. Reverse-proxy trust, isolated from Caddy ────────────────────────────────
#
# HA rejects *any* request carrying an X-Forwarded-For header unless the TCP
# peer itself (not the header's claimed value — verified against the real
# 2026.8.2 image by sending an obviously-foreign XFF value from a trusted peer
# and getting 200 back) is inside http.trusted_proxies; an untrusted peer 400s
# whether the route is /api/ or a plain static asset like /manifest.json.
# entrypoint.sh's whole job is making HA trust EXIST_DOCKER_SUBNET (the `exist`
# bridge Caddy sits on) — and this container (adhoc/decree) is itself a peer on
# that same bridge, so sending a request with any XFF header straight at
# homeassistant:8123, bypassing Caddy, exercises exactly the trust decision
# Caddy's own connections depend on. A failure here means "entrypoint.sh's
# .storage/http patch did not take" specifically — not "Caddy is misrouting"
# (the probe above) and not "HA is down" (check 1).
#
# Only meaningful against the shared default (nobody else in the repo sets
# EXIST_DOCKER_SUBNET — grep confirms homeassistant is its only reader): a
# custom CIDR could in principle exclude this container's own bridge address,
# which would make a 400 here ambiguous rather than a real finding.
if [ -z "${EXIST_DOCKER_SUBNET:-}" ]; then
    http_probe "homeassistant trusted_proxies (direct, bypassing caddy)" \
        "${HA_URL}/manifest.json" 200 5 \
        -H "X-Forwarded-For: 172.20.0.1" -H "X-Forwarded-Proto: https"
else
    skip "homeassistant trusted_proxies (direct, bypassing caddy)" \
         "EXIST_DOCKER_SUBNET is customized — can't pick a guaranteed in-range probe IP"
fi

finish
