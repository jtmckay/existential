#!/usr/bin/env bash
# exist.test.sh — validate the automation-webhook receiver.
#
# Read-only by design. The webhook's success path writes a file into the inbox
# that the decree daemon then *executes*, so this script never sends an
# authenticated POST — it exercises only /healthz and the rejection paths.
#
# See .claude/reference/testing.md for the convention.

set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../src/test" && pwd)/exist-test.sh"
exist_self_elevate
exist_test_init "automation-webhook" EXIST_IS_SERVICES_AUTOMATION_WEBHOOK
skip_if_disabled

load_env_exist

# The webhook is reached only over the exist bridge (ports: stays commented out),
# so its listen port is not configurable — decree-go-rest's own default governs,
# and caddy's Caddyfile hardcodes the same value.
WEBHOOK="http://automation-webhook:8801"

# ── 1. Webhook liveness ──────────────────────────────────────────────────────

http_probe "automation-webhook /healthz" "${WEBHOOK}/healthz" 200

# Routing coverage — same endpoint through caddy, so "webhook down" stays
# distinguishable from "caddy/pihole routing broken".
probe_caddy "automation-webhook /healthz" automation-webhook /healthz 200

# ── 2. Rejection paths ───────────────────────────────────────────────────────
#
# These three requests each consume one slot of the failure rate limiter
# (rate_fail_max in automation/decree-go-rest.yml, default 10 per 60s). That budget
# is in-memory and self-heals within the window, but it is why this section stays
# at three requests rather than exhaustively enumerating rejection cases —
# decree-go-rest's own test suite covers those, off the live stack.
#
# 429 is accepted alongside the specific code. Running this suite several times
# inside one 60s window — a fix-and-retest loop, or `test services` followed by
# e2e — legitimately exhausts the budget, and a rejected request is still a
# rejected request. Asserting 401 exactly would fail on the limiter *working*.

http_probe_any "unauthenticated POST rejected" "${WEBHOOK}/notify" '^(401|429)$' 5 \
    -X POST --data-binary 'exist.test.sh probe'

http_probe_any "bad bearer token rejected" "${WEBHOOK}/notify" '^(401|429)$' 5 \
    -X POST --data-binary 'exist.test.sh probe' \
    -H 'Authorization: Bearer not-the-real-secret'

http_probe_any "unknown path 404s" "${WEBHOOK}/exist-test-no-such-endpoint" '^(404|429)$' 5 \
    -X POST --data-binary 'exist.test.sh probe'

finish
