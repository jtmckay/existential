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
OPENVIKING_API_KEY="${OPENVIKING_API_KEY:-}"

# ── 1. Health (unauthenticated) ───────────────────────────────────────────────

probe_service "openviking /health" openviking 1933 /health 200

# ── 2. API key configured ─────────────────────────────────────────────────────

if [[ -z "${OPENVIKING_API_KEY:-}" ]]; then
    warn "openviking API key configured" \
         "OPENVIKING_API_KEY is empty" \
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

# ── 5. Embedding model reachable ─────────────────────────────────────────────
#
# The failure this catches is genuinely invisible from the outside: uploads keep
# succeeding, the file appears in the viking:// tree, and only the vector half
# is missing — so search returns nothing and everything else looks healthy.
# OpenViking logs "Failed to generate embedding ... not found, try pulling it
# first" and opens a circuit breaker; nothing surfaces that but its own log.

# ov.conf is reachable two different ways depending on who is running this.
# From adhoc and from the decree daemon (triage) the whole repo is mounted at
# /repo; a daemon that mounts volumes/ instead sees the data volume at
# /volumes/openviking_data. A bare /repo path works in one and not the other, so
# try both — this file is also run as a health gate, and getting it wrong wedges
# the caller for its full 300s startup timeout.
OV_CONF=""
for _c in /repo/volumes/openviking_data/ov.conf /volumes/openviking_data/ov.conf; do
    [[ -f "$_c" ]] && { OV_CONF="$_c"; break; }
done

# `|| true` is load-bearing under `set -o pipefail`: sed on a missing file exits
# non-zero, which takes the whole assignment — and the script — down with it.
EMBED_MODEL=$(sed -n 's/^[[:space:]]*"model"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
    "${OV_CONF:-/dev/null}" 2>/dev/null | head -1 || true)
EMBED_BASE=$(sed -n 's/.*"api_base"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
    "${OV_CONF:-/dev/null}" 2>/dev/null | head -1 || true)

if [[ -z "${EMBED_MODEL}" || -z "${EMBED_BASE}" ]]; then
    warn "openviking embedding model available" \
         "could not read model/api_base from volumes/openviking_data/ov.conf" \
         "./existential.sh run openviking   (writes ov.conf)"
else
    TAGS=$(curl -sS --max-time 10 "${EMBED_BASE%/v1}/api/tags" 2>/dev/null || true)
    if [[ -z "${TAGS}" ]]; then
        warn "openviking embedding model available" \
             "no response from ${EMBED_BASE%/v1}/api/tags" \
             "Is ollama up and EXIST_OLLAMA_URL correct? docker logs ollama"
    elif printf '%s' "${TAGS}" | grep -q "\"${EMBED_MODEL}"; then
        ok "openviking embedding model available (${EMBED_MODEL})"

        # The other half of the same silent failure. OpenViking validates every
        # vector against ov.conf's `dimension` and DROPS the ones that disagree
        # ("Dense vector dimension mismatch: expected N, got M" — storage/
        # collection_schemas.py). Uploads still return ok, the file still shows
        # up in the viking:// tree, and search still returns nothing. Nothing
        # asserts EXIST_MODEL_EMBED and EXIST_MODEL_EMBED_DIM agree once the
        # user has edited .env.shared, so ask the model itself.
        WANT_DIM=$(sed -n 's/.*"dimension"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p' \
            "${OV_CONF}" 2>/dev/null | head -1 || true)
        GOT_DIM=$(curl -sS --max-time 30 "${EMBED_BASE%/v1}/api/embed" \
            -d "{\"model\": \"${EMBED_MODEL}\", \"input\": \"dimension probe\"}" 2>/dev/null \
            | jq -r '.embeddings[0] | length' 2>/dev/null || true)
        if [[ -z "${WANT_DIM}" || -z "${GOT_DIM}" || "${GOT_DIM}" == "null" ]]; then
            warn "openviking embedding dimension matches the model" \
                 "could not probe ${EMBED_MODEL} on ${EMBED_BASE%/v1}" \
                 "curl ${EMBED_BASE%/v1}/api/embed -d '{\"model\":\"${EMBED_MODEL}\",\"input\":\"x\"}'"
        elif [[ "${WANT_DIM}" == "${GOT_DIM}" ]]; then
            ok "openviking embedding dimension matches the model (${GOT_DIM})"
        else
            fail "openviking embedding dimension matches the model" \
                 "ov.conf says ${WANT_DIM}, ${EMBED_MODEL} returns ${GOT_DIM} — every vector is dropped, so search returns nothing" \
                 "Set EXIST_MODEL_EMBED_DIM=${GOT_DIM} in .env.shared, delete volumes/openviking_data/ov.conf and the stale index, then ./existential.sh run openviking"
        fi
    else
        fail "openviking embedding model available" \
             "${EMBED_MODEL} is not pulled on ${EMBED_BASE%/v1} — uploads succeed but nothing is embedded, so search returns nothing" \
             "./existential.sh run ollama pull-models"
    fi
fi

# ── 6. Knowledgebase wiring ──────────────────────────────────────────────────
#
# workspace/ is the user's own directory, so an empty one is fine — but a MISSING
# one means openviking is indexing nothing, and the only other symptom is
# searches quietly returning less than they should.

# The decree daemon sees the knowledgebase at /workspace — that mount IS the
# wiring under test, so checking it there is the stronger assertion. From adhoc
# the same directory is /repo/workspace.
VIKING_DIR=""
for _v in /workspace /repo/workspace; do
    [[ -d "$_v" ]] && { VIKING_DIR="$_v"; break; }
done

if [[ -n "$VIKING_DIR" ]]; then
    ok "openviking knowledgebase readable at ${VIKING_DIR} ($(find "$VIKING_DIR" -type f 2>/dev/null | wc -l) file(s))"
else
    fail "openviking knowledgebase readable" \
         "neither /workspace (indexer mount) nor /repo/workspace is present" \
         "./existential.sh   (creates workspace/ and mounts it), then: docker compose up -d decree"
fi

# Repo-wide checks only work where the repo is mounted. Where it isn't, the
# mount above already proves the same wiring, so skip rather than fail.
if [[ -d /repo ]]; then
    if [[ -f /repo/docker-compose.yml ]] && grep -qE '^\s+- \./workspace:/workspace' /repo/docker-compose.yml; then
        ok "openviking knowledgebase mounted into the indexer"
    else
        warn "openviking knowledgebase mounted into the indexer" \
             "no ./workspace:/workspace mount in the generated docker-compose.yml" \
             "./existential.sh   (re-generates it; if ai/openviking/docker-compose.yml is stale, edit it or ./existential.sh reset)"
    fi

    # Without an active cron nothing ever indexes, and the only symptom is
    # searches quietly returning nothing. The indexer is a routine of the main
    # decree daemon, so its cron lives in that daemon's project dir — openviking
    # ships no decree/ of its own. Quest activates it (`copies` in 00-core.md).
    if compgen -G "/repo/automation/cron/*openviking-index*" >/dev/null; then
        ok "openviking indexer cron active"
    else
        warn "openviking indexer cron active" \
             "no openviking-index cron in automation/cron/" \
             "cp automation-examples/cron/openviking-index-knowledgebase.md automation/cron/, then: docker compose restart automation"
    fi
fi

finish
