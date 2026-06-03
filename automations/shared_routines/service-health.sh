#!/usr/bin/env bash
# service-health — HTTP/TCP probe for a single service endpoint.
#
# Intended to run inside the main decree daemon (on the exist Docker network)
# on a cron schedule. The decree afterEach hook automatically:
#   - Pushes decree_run_success{instance="health-<service>"} to Prometheus
#   - Ships the run log to Loki
# so every execution is visible in Grafana with no extra wiring.
#
# Cron frontmatter keys:
#   SERVICE_NAME   Display name and Prometheus instance label suffix (required)
#   SERVICE_URL    Full HTTP URL to probe (required)
#   EXPECT_CODE    Expected HTTP status code (default: 200)
#   TIMEOUT        Curl timeout in seconds (default: 5)
#
# Example cron file:
#   ---
#   cron: "*/15 * * * *"
#   routine: service-health
#   SERVICE_NAME: mealie
#   SERVICE_URL: http://mealie:9000/api/app/about
#   ---
#
# Manual invocation:
#   docker exec decree decree run service-health

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ "${DECREE_PRE_CHECK:-}" = "true" ]; then
    source "${SCRIPT_DIR}/../lib/precheck.sh"
    command -v curl >/dev/null || precheck_fail "service-health" "curl not found"
    precheck_pass "service-health"
    exit 0
fi

SERVICE_NAME="${SERVICE_NAME:?SERVICE_NAME is required in cron frontmatter}"
SERVICE_URL="${SERVICE_URL:?SERVICE_URL is required in cron frontmatter}"
EXPECT_CODE="${EXPECT_CODE:-200}"
TIMEOUT="${TIMEOUT:-5}"

printf '[%s] probe %s\n' "$SERVICE_NAME" "$SERVICE_URL"

http_code=$(curl -fsS -o /dev/null -w "%{http_code}" \
    --max-time "$TIMEOUT" --connect-timeout "$TIMEOUT" \
    "$SERVICE_URL" 2>/dev/null || echo "000")

if [[ "$http_code" == "$EXPECT_CODE" ]]; then
    printf '[%s] HTTP %s  OK\n' "$SERVICE_NAME" "$http_code"
elif [[ "$http_code" == "000" ]]; then
    printf '[%s] no response within %ss  FAIL\n' "$SERVICE_NAME" "$TIMEOUT" >&2
    exit 1
else
    printf '[%s] HTTP %s (expected %s)  FAIL\n' "$SERVICE_NAME" "$http_code" "$EXPECT_CODE" >&2
    exit 1
fi
