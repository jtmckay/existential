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

# Both /ready probes above only prove each HTTP server answers — neither proves
# alloy is actually shipping logs into loki. Query loki's own store for the
# docker_containers job instead: every container (loki and loki-alloy included)
# writes json-file log lines from its own startup, and alloy tails from byte 0
# on a fresh positions file (verified: a line written before alloy's first
# start still showed up in a query afterward), so a working pipeline has
# entries within seconds. A stale bind mount or a relabel/pipeline regression
# that drops every line shows up here as zero entries instead of a Grafana
# panel that is quietly empty.
_docker_job_lines=""
for _attempt in 1 2 3 4 5 6 7 8; do
    _resp=$(curl -sS --max-time 10 -G "http://loki:3100/loki/api/v1/query_range" \
        --data-urlencode 'query={job="docker"}' \
        --data-urlencode "start=$(( $(date +%s) - 300 ))000000000" \
        --data-urlencode 'limit=5' 2>/dev/null || true)
    _docker_job_lines=$(printf '%s' "$_resp" | jq -r '[.data.result[]?.values[]?] | length' 2>/dev/null || echo 0)
    [ "${_docker_job_lines:-0}" -ge 1 ] 2>/dev/null && break
    sleep 2
done
if [ "${_docker_job_lines:-0}" -ge 1 ]; then
    ok "loki-alloy shipping docker logs into loki"
else
    fail "loki-alloy shipping docker logs into loki" \
         "no {job=\"docker\"} entries in loki from the last 5 minutes" \
         "Check: docker logs loki-alloy | tail -50; and that /var/lib/docker/containers is mounted: docker inspect loki-alloy | grep -A2 docker/containers"
fi

finish
