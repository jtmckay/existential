#!/usr/bin/env bash
# exist.test.sh — validate that loki + loki-alloy are operational.
#
# See .claude/reference/testing.md for the convention.

set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../src/test" && pwd)/exist-test.sh"
exist_self_elevate
exist_test_init "loki" EXIST_IS_HOSTING_LOKI
skip_if_disabled

# loki default HTTP listener is :3100. /ready is the standard health endpoint,
# but it stays 503 until the ingester has been ACTIVE in the ring for ~15s after
# WAL replay — roughly a 20s cold start. Give it a generous retry budget
# (30 × 2s ≈ 60s) so a freshly-started loki isn't a false failure.
EXIST_PROBE_RETRIES=30 http_probe "loki:3100 /ready"      "http://loki:3100/ready"      200

# alloy readiness on :12345 (its UI/health port, deliberately not routed through
# Caddy — loki has no route either). /-/ready is 503 until every component has
# evaluated, and unreachable (000) until the HTTP server binds; both mean "warming
# up", so keep a loki-sized budget rather than failing inside the startup window.
EXIST_PROBE_RETRIES=30 EXIST_PROBE_RETRY_CODES="000 500 503" \
    http_probe "loki-alloy:12345 /-/ready" "http://loki-alloy:12345/-/ready" 200

finish
