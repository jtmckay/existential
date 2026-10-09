#!/usr/bin/env bash
# service_health — HTTP probe for a single service endpoint.
#
# Runs in the main decree daemon (on the exist Docker network) on a cron
# schedule. Every run lands in Loki and in decree_runs_total{machine=
# "service_health"}, so a failing probe is a failed run — and a Grafana alert.
#
# SERVICE_NAME, SERVICE_URL, EXPECT_CODE and TIMEOUT are the machine's data:
#
#   ---
#   cron: "*/15 * * * *"
#   machine: service_health
#   params:
#     SERVICE_NAME: mealie
#     SERVICE_URL: http://mealie:9000/api/app/about
#   ---
set -euo pipefail

SERVICE_NAME="${DECREE_DATA_SERVICE_NAME:?SERVICE_NAME is required in the cron file's params}"
SERVICE_URL="${DECREE_DATA_SERVICE_URL:?SERVICE_URL is required in the cron file's params}"
EXPECT_CODE="$DECREE_DATA_EXPECT_CODE"
TIMEOUT="$DECREE_DATA_TIMEOUT"

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
