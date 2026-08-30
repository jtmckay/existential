#!/usr/bin/env bash
# exist.test.sh — validate that openviking is fully operational.
#
# See .claude/reference/testing.md for the convention.

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
    -H "X-OpenViking-Account: default" \
    -H "X-OpenViking-User: default" \
    "${OPENVIKING_URL}/api/v1/fs/ls?uri=viking://" 2>/dev/null || echo "000")
case "${CODE}" in
    200) ok "openviking filesystem API" ;;
    401) fail "openviking filesystem API" \
              "401 unauthorized — API key mismatch" \
              "Check OPENVIKING_API_KEY matches root_api_key in volumes/openviking_data/ov.conf" ;;
    000) fail "openviking filesystem API" \
              "no response within 10s" \
              "docker logs openviking" ;;
    400) fail "openviking filesystem API" \
              "400 — tenant-scoped API rejected the request" \
              "A ROOT key must send X-OpenViking-Account + X-OpenViking-User; check openviking has not changed those header names" ;;
    *)   fail "openviking filesystem API" \
              "HTTP ${CODE}" \
              "docker logs openviking" ;;
esac

# ── 4. Caddy routing ──────────────────────────────────────────────────────────

probe_caddy "openviking /health" openviking /health 200

# ── 5. Notes and resources dirs mounted ──────────────────────────────────────

# Both are declared volumes now, so generate-compose.ts creates them for an
# enabled openviking — a missing one means the render never ran.
[[ -d /repo/volumes/openviking_notes_data ]] \
    && ok "openviking notes volume present" \
    || fail "openviking notes volume present" \
             "missing volumes/openviking_notes_data/" \
             "./existential.sh"

[[ -d /repo/volumes/openviking_resources_data ]] \
    && ok "openviking resources volume present" \
    || fail "openviking resources volume present" \
             "missing volumes/openviking_resources_data/" \
             "./existential.sh"

# ── 6. Knowledgebase mounted and watched ─────────────────────────────────────
#
# viking/ is the user's own directory, so an empty one is fine — but a MISSING
# one means openviking is indexing nothing, and the only other symptom is
# searches quietly returning less than they should.

if [[ -d /repo/viking ]]; then
    ok "openviking knowledgebase dir present ($(find /repo/viking -type f 2>/dev/null | wc -l) file(s))"
else
    fail "openviking knowledgebase dir present" \
         "missing viking/ at the repo root" \
         "./existential.sh run openviking   (creates it)"
fi

# The mount is what openviking actually indexes; the host dir existing does not
# prove the container got it (a stale rendered compose file would not have it).
if [[ -f /repo/docker-compose.yml ]] && grep -qE '^\s+- \./viking:/app/viking' /repo/docker-compose.yml; then
    ok "openviking knowledgebase mounted at /app/viking"
else
    warn "openviking knowledgebase mounted at /app/viking" \
         "no ./viking:/app/viking mount in the generated docker-compose.yml" \
         "./existential.sh   (re-generates it; if ai/openviking/docker-compose.yml is stale, edit it or ./existential.sh reset)"
fi

finish
