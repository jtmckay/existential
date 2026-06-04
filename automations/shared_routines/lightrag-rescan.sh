#!/usr/bin/env bash
# LightRAG Rescan
#
# Triggers an incremental rescan of the Obsidian vault by calling LightRAG's
# /documents/scan endpoint. New and modified files are chunked, entities and
# relationships are extracted by LightRAG's configured Ollama model (see
# ai/lightrag/.env), and the graph store is updated.
#
# Wired up nightly via automations/cron/lightrag-rescan.md. Can also be invoked
# on demand with: docker exec decree decree run lightrag-rescan
set -euo pipefail

if [ "${DECREE_PRE_CHECK:-}" = "true" ]; then
    # shellcheck source=../lib/precheck.sh
    source "$(dirname "${BASH_SOURCE[0]}")/../lib/precheck.sh"
    command -v curl >/dev/null 2>&1 || precheck_fail "lightrag-rescan" "curl not found"
    [ -n "${LIGHTRAG_API_KEY:-}" ] || precheck_fail "lightrag-rescan" "LIGHTRAG_API_KEY is not set"
    precheck_pass "lightrag-rescan"
    exit 0
fi

LIGHTRAG_URL="${LIGHTRAG_URL:-http://lightrag:9621}"

: "${LIGHTRAG_API_KEY:?LIGHTRAG_API_KEY is not set}"

if ! curl -fsS -X POST "${LIGHTRAG_URL}/documents/scan" \
        -H "X-API-Key: ${LIGHTRAG_API_KEY}" >/dev/null; then
    echo "LightRAG rescan failed" >&2
    exit 1
fi

echo "LightRAG vault rescan triggered"
