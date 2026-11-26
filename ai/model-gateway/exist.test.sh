#!/usr/bin/env bash
# exist.test.sh — the model gateway answers, keeps out a call without the fleet
# secret, and lists what the fleet offers. Read-only: it starts no lease.
#
# See .claude/reference/testing.md for the convention.

set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../src/test" && pwd)/exist-test.sh"
exist_self_elevate
exist_test_init "model-gateway" EXIST_IS_AI_MODEL_GATEWAY
skip_if_disabled

load_env_exist

URL="${MODEL_GATEWAY_URL:-http://model-gateway:4400}"

if curl -fsS --max-time 5 "${URL}/health" >/dev/null 2>&1; then
    ok "model-gateway /health"
else
    fail "model-gateway /health" "no answer at ${URL}/health" "docker logs model-gateway"
fi

CODE=$(curl -sS -o /dev/null -w "%{http_code}" --max-time 5 "${URL}/v1/models" 2>/dev/null || echo 000)
if [ "$CODE" = 401 ] || [ "$CODE" = 503 ]; then
    ok "model-gateway refuses a call without the fleet secret (HTTP ${CODE})"
else
    fail "model-gateway refuses a call without the fleet secret" "HTTP ${CODE}" "gateway.ts checks the Authorization header"
fi

if [ -n "${EXIST_FLEET_SECRET:-}" ]; then
    OUT=$(curl -fsS --max-time 30 -H "Authorization: Bearer ${EXIST_FLEET_SECRET}" "${URL}/v1/models" 2>/dev/null || true)
    if printf '%s' "$OUT" | jq -e '.object == "list"' >/dev/null 2>&1; then
        ok "model-gateway lists the fleet's models ($(printf '%s' "$OUT" | jq '.data | length') now)"
    else
        fail "model-gateway lists the fleet's models" "got: ${OUT:-nothing}" "./existential.sh run peers llm"
    fi
fi

finish
