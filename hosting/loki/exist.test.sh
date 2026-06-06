#!/usr/bin/env bash
# exist.test.sh — validate that loki + loki-promtail are operational.
#
# See CLAUDE.md "Service test scripts" for the convention.

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

# promtail readiness on :9080. /ready emits a transient 500 (then 200) during cold
# start, and isn't reachable at all (000) until its HTTP server binds — both are
# "warming up", so retry on 000/500/503 with a loki-sized budget rather than failing
# the instant we catch the startup window.
EXIST_PROBE_RETRIES=30 EXIST_PROBE_RETRY_CODES="000 500 503" \
    http_probe "loki-promtail:9080 /ready" "http://loki-promtail:9080/ready" 200

finish
