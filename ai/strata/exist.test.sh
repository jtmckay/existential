#!/usr/bin/env bash
# exist.test.sh — validate that strata serves a model the stack can reach.
#
# See .claude/reference/testing.md for the convention.
# Run via: ./existential.sh run strata test  (or: ./existential.sh test)

set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../src/test" && pwd)/exist-test.sh"
exist_self_elevate
exist_test_init "strata" EXIST_IS_AI_STRATA
skip_if_disabled
load_env_exist

# /health answers without the key, during download and load too.
probe_service "strata /health" strata 8080 /health 200

# /v1/models takes the stack's key, so a 401 here is every model call's 401.
MODELS=$(curl -sS --max-time 10 -H "Authorization: Bearer ${EXIST_FLEET_SECRET:-}" \
    -w '\n%{http_code}' http://strata:8080/v1/models 2>/dev/null || true)
CODE="${MODELS##*$'\n'}"
IDS=$(printf '%s' "${MODELS%$'\n'*}" | jq -r '.data[]?.id // empty' 2>/dev/null | tr '\n' ' ' || true)
case "$CODE" in
    200) ok "strata /v1/models with the stack's key — serving: ${IDS:-nothing yet}" ;;
    401) fail "strata /v1/models with the stack's key" "401" \
              "strata and the stack disagree on EXIST_FLEET_SECRET (.env.shared): ./existential.sh && docker compose up -d strata" ;;
    *)   skip "strata /v1/models with the stack's key" \
              "HTTP ${CODE:-none}: still downloading or loading — docker logs -f strata" ;;
esac

# When model calls go to this container, the tag they send must be one strata serves.
if [ "$CODE" = 200 ] && [ "${EXIST_MODEL_URL:-}" = "http://strata:8080/v1" ]; then
    case " $IDS " in
        *" ${EXIST_MODEL_CHAT:-} "*) ok "EXIST_MODEL_CHAT is served by strata" ;;
        *) fail "EXIST_MODEL_CHAT is served by strata" "'${EXIST_MODEL_CHAT:-}' not in: ${IDS}" \
                "Set EXIST_MODEL_CHAT (and _VISION) in .env.shared to the id above" ;;
    esac
fi

finish
