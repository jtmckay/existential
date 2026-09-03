#!/usr/bin/env bash
# exist.test.sh — validate prometheus, pushgateway and node-exporter.
#
# See .claude/reference/testing.md for the convention.

set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../src/test" && pwd)/exist-test.sh"
exist_self_elevate
exist_test_init "prometheus" EXIST_IS_HOSTING_PROMETHEUS
skip_if_disabled

probe_service "prometheus /-/healthy" prometheus 9090 /-/healthy 200
probe_service "prometheus /-/ready"   prometheus 9090 /-/ready   200

# pushgateway and node-exporter are not fronted by caddy — direct only.
http_probe "prometheus-pushgateway /-/healthy" \
           "http://prometheus-pushgateway:9091/-/healthy" 200

# node-exporter serves no /-/healthy endpoint; /metrics is the liveness signal.
http_probe "prometheus-node-exporter /metrics" \
           "http://prometheus-node-exporter:9100/metrics" 200

# Every /-/healthy above only proves each web server accepts connections — it
# says nothing about whether prometheus.yml's scrape_configs actually resolve
# and reach those containers. Query prometheus's own `up` series (one sample
# per scrape_configs job in prometheus.yml) so a stale/typo'd target (e.g. a
# renamed container) fails here instead of silently going dark in the TSDB.
#
# A target's first `up` sample only appears once its first scrape has run —
# measured on a cold prometheus container (empty TSDB, 15s scrape_interval)
# all 3 jobs took ~15s to appear, in step with the interval, not sooner. Retry
# instead of failing a prometheus that only just started.
UP_JSON=""
for _attempt in 1 2 3 4 5 6 7 8; do
    UP_JSON=$(curl -sS --max-time 10 "http://prometheus:9090/api/v1/query" --data-urlencode 'query=up' 2>/dev/null || true)
    JOB_COUNT=$(printf '%s' "$UP_JSON" | jq -r '.data.result | length' 2>/dev/null || echo 0)
    [ "${JOB_COUNT:-0}" -ge 3 ] 2>/dev/null && break
    sleep 2
done
DOWN_JOBS=$(printf '%s' "$UP_JSON" | jq -r '.data.result[] | select(.value[1] != "1") | .metric.job' 2>/dev/null || echo "?")
JOB_COUNT=$(printf '%s' "$UP_JSON" | jq -r '.data.result | length' 2>/dev/null || echo 0)
if [ "$DOWN_JOBS" = "?" ] || [ -z "$UP_JSON" ]; then
    fail "prometheus scrape targets up" "/api/v1/query did not return JSON: ${UP_JSON:-<no response>}" \
         "Check: docker logs prometheus"
elif [ -n "$DOWN_JOBS" ]; then
    fail "prometheus scrape targets up" "job(s) reporting up=0: $(printf '%s' "$DOWN_JOBS" | tr '\n' ' ')" \
         "Check http://prometheus:9090/targets for the scrape error, and that the target container is running"
elif [ "$JOB_COUNT" -lt 3 ]; then
    fail "prometheus scrape targets up" "expected 3 targets (prometheus, pushgateway, node), got ${JOB_COUNT}" \
         "prometheus.yml's scrape_configs and this test have drifted apart — compare the two"
else
    ok "prometheus scrape targets up"
fi

finish
