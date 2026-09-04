#!/usr/bin/env bash
# exist.test.sh — validate the decree daemon's supporting state and the
# automation-webhook receiver.
#
# Read-only by design. The webhook's success path writes a file into the inbox
# that the decree daemon then *executes*, so this script never sends an
# authenticated POST — it exercises only /healthz and the rejection paths.
#
# See .claude/reference/testing.md for the convention.

set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../src/test" && pwd)/exist-test.sh"
exist_self_elevate
exist_test_init "automation" EXIST_IS_SERVICES_AUTOMATION
skip_if_disabled

load_env_exist

# The webhook is reached only over the exist bridge (ports: stays commented out),
# so its listen port is not configurable — the binary's own default governs, and
# caddy's Caddyfile hardcodes the same value.
WEBHOOK="http://automation-webhook:8801"

# ── 1. Rendered state ────────────────────────────────────────────────────────

file_present "webhook config rendered" /repo/services/automation/webhook/config.yml
file_present "decree inbox present" /repo/automation/inbox

# ── 2. Webhook liveness ──────────────────────────────────────────────────────

http_probe "automation-webhook /healthz" "${WEBHOOK}/healthz" 200

# Routing coverage — same endpoint through caddy, so "webhook down" stays
# distinguishable from "caddy/pihole routing broken".
probe_caddy "automation-webhook /healthz" automation-webhook /healthz 200

# ── 3. Rejection paths ───────────────────────────────────────────────────────
#
# These three requests each consume one slot of the failure rate limiter
# (DECREE_WEBHOOK_RATE_FAIL_MAX, default 10 per 60s). That budget is in-memory
# and self-heals within the window, but it is why this section stays at three
# requests rather than exhaustively enumerating rejection cases — webhook/main_test.go
# covers those exhaustively, off the live stack.
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
