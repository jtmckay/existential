#!/usr/bin/env bash
# exist.test.sh — validate that openviking is fully operational.
#
# See CLAUDE.md "Service test scripts" for the convention.

set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../src/test" && pwd)/exist-test.sh"
exist_self_elevate
exist_test_init "openviking" EXIST_IS_AI_OPENVIKING
skip_if_disabled

OPENVIKING_URL="${OPENVIKING_URL:-http://openviking:1933}"
OPENVIKING_API_KEY="${OPENVIKING_API_KEY:-${EXIST_OPENVIKING_API_KEY:-}}"

# ── 1. Health (unauthenticated) ───────────────────────────────────────────────

probe_service "openviking /health" openviking 1933 /health 200

# ── 2. API key configured ─────────────────────────────────────────────────────

if [[ -z "${OPENVIKING_API_KEY:-}" ]]; then
    warn "openviking API key configured" \
         "EXIST_OPENVIKING_API_KEY is empty" \
         "Re-run ./existential.sh run after setting OPENVIKING_API_KEY in .env"
else
    ok "openviking API key configured"
fi

# ── 3. Filesystem list (authenticated) ───────────────────────────────────────

CODE=$(curl -sS -o /dev/null -w "%{http_code}" --max-time 10 \
    -H "Authorization: Bearer ${OPENVIKING_API_KEY:-}" \
    "${OPENVIKING_URL}/api/v1/fs/ls?uri=viking://" 2>/dev/null || echo "000")
case "${CODE}" in
    200) ok "openviking filesystem API" ;;
    401) fail "openviking filesystem API" \
              "401 unauthorized — API key mismatch" \
              "Check OPENVIKING_API_KEY matches root_api_key in volumes_local/openviking_data/ov.conf" ;;
    000) fail "openviking filesystem API" \
              "no response within 10s" \
              "docker logs openviking" ;;
    *)   fail "openviking filesystem API" \
              "HTTP ${CODE}" \
              "docker logs openviking" ;;
esac

# ── 4. Caddy routing ──────────────────────────────────────────────────────────

probe_caddy "openviking /health" openviking /health 200

# ── 5. Notes and resources dirs mounted ──────────────────────────────────────

[[ -d /repo/ai/openviking/notes ]] \
    && ok "openviking notes/ directory present" \
    || fail "openviking notes/ directory present" \
             "missing ai/openviking/notes/" \
             "git checkout ai/openviking/notes/.gitkeep"

[[ -d /repo/ai/openviking/resources ]] \
    && ok "openviking resources/ directory present" \
    || fail "openviking resources/ directory present" \
             "missing ai/openviking/resources/" \
             "git checkout ai/openviking/resources/.gitkeep"

finish
