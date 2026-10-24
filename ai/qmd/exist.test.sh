#!/usr/bin/env bash
# exist.test.sh — validate that qmd answers keyword AND neural searches.
#
# See .claude/reference/testing.md for the convention. Read-only: a status call
# and two searches.

set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../src/test" && pwd)/exist-test.sh"
exist_self_elevate
exist_test_init "qmd" EXIST_IS_AI_QMD
skip_if_disabled

QMD_URL="${QMD_URL:-http://qmd:8181}"

# ── 1. Listening ─────────────────────────────────────────────────────────────

# Direct only: qmd has no Caddy hostname (it is never published), so
# probe_service's Caddy layer would fail on every install with Caddy on.
http_probe "qmd /health" "${QMD_URL}/health" 200

# ── 2. Index status ──────────────────────────────────────────────────────────
#
# The MCP status tool is the same answer the agent gets. qmd's HTTP MCP is
# stateless, so one call needs no session. The reply is one SSE `data:` line.

STATUS=$(curl -sS --max-time 15 "${QMD_URL}/mcp" -H 'Host: qmd:8181' \
    -H 'Content-Type: application/json' -H 'Accept: application/json, text/event-stream' \
    -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"status","arguments":{}}}' 2>/dev/null \
    | sed -n 's/^data: //p' | jq -c '.result.structuredContent' 2>/dev/null || true)
DOCS=$(jq -r '.totalDocuments // empty' <<<"${STATUS:-null}" 2>/dev/null || true)
PENDING=$(jq -r '.needsEmbedding // empty' <<<"${STATUS:-null}" 2>/dev/null || true)

if [[ -z "${DOCS}" ]]; then
    fail "qmd index status" "no status from ${QMD_URL}/mcp" "docker logs qmd"
elif [[ "${DOCS}" == 0 ]]; then
    warn "qmd has indexed the workspace" "0 Markdown files indexed" \
         "A fresh workspace may have none yet; otherwise docker logs qmd"
else
    ok "qmd has indexed the workspace (${DOCS} file(s))"
fi

# Files with no vectors are found by keyword only. During the first start that
# is the model still downloading; after a refresh pass it is a failure, and
# entrypoint.sh has logged why (refresh.status says which).
# adhoc sees the volume under /repo; the backup daemon (triage) under /volumes.
REFRESH=""
for _s in /repo/volumes/qmd_cache/refresh.status /volumes/qmd_cache/refresh.status; do
    [[ -f "$_s" ]] && { REFRESH=$(cat "$_s"); break; }
done
if [[ -n "${PENDING}" && "${PENDING}" != 0 ]]; then
    if [[ "${REFRESH}" == keyword-only* ]]; then
        fail "qmd neural index ready" \
             "${PENDING} file(s) have no vectors: search finds them by keyword only" \
             "docker logs qmd | grep 'NEURAL INDEX'   (a model download that failed is retried every refresh)"
    else
        warn "qmd neural index ready" "${PENDING} file(s) still being embedded (first start?)" \
             "Wait a minute and re-run: ./existential.sh run qmd test"
    fi
elif [[ -n "${PENDING}" ]]; then
    ok "qmd neural index ready (every file has vectors)"
fi

# PDF and Word files are converted to text before indexing; one with no text
# layer (a scan: there is no OCR) is recorded instead, and is not searchable.
for _d in /repo/volumes/qmd_cache/documents /volumes/qmd_cache/documents; do
    [[ -d "$_d" ]] || continue
    CONVERTED=$(find "$_d" -name '*.md' | wc -l); NOTEXT=$(find "$_d" -name '*.none' | wc -l)
    ok "qmd indexes ${CONVERTED} PDF/Word file(s)"
    if (( NOTEXT > 0 )); then
        warn "every PDF/Word file has text" "${NOTEXT} have no text layer (scans; OCR is not supported), so search can't see them" \
             "docker logs qmd | grep 'not searchable'"
    fi
    break
done

# ── 3. Both halves of a search answer ────────────────────────────────────────
search() {  # <type> <query>
    curl -sS --max-time 30 "${QMD_URL}/query" -H 'Host: qmd:8181' -H 'Content-Type: application/json' \
        -d "$(jq -n --arg t "$1" --arg q "$2" '{searches: [{type: $t, query: $q}], limit: 3, rerank: false}')" 2>/dev/null || true
}
if [[ "${DOCS:-0}" != 0 ]]; then
    VEC=$(search vec "notes about my plans and decisions")
    VEC_N=$(jq -r '.results | length' <<<"${VEC:-null}" 2>/dev/null || echo 0)
    if [[ "${VEC_N:-0}" -gt 0 ]]; then
        ok "qmd neural search answers"
    else
        fail "qmd neural search answers" "no results from a vec query: ${VEC:-no response}" "docker logs qmd"
    fi
    # lex terms are prefixes, so "e" matches nearly any note in any language.
    LEX_N=$(jq -r '.results | length' <<<"$(search lex e)" 2>/dev/null || echo 0)
    if [[ "${LEX_N:-0}" -gt 0 ]]; then
        ok "qmd keyword search answers"
    else
        fail "qmd keyword search answers" "no results for a one-letter keyword prefix" "docker logs qmd"
    fi
fi

# The terminal command (`search` in code-server, `run qmd search` on the host).
if [[ "${DOCS:-0}" != 0 ]]; then
    _cli="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/automation/lib/recall/search.sh"
    if EXIST_SEARCH_MCP_URL="${QMD_URL}/mcp" "$_cli" e >/dev/null 2>&1; then
        ok "the search command answers"
    else
        fail "the search command answers" "automation/lib/recall/search.sh e failed" "./existential.sh run qmd search e"
    fi
fi

# ── 4. Something uses it ─────────────────────────────────────────────────────

if [[ -z "${EXIST_SEARCH_MCP_URL:-}" ]]; then
    warn "a client is connected to qmd" "EXIST_SEARCH_MCP_URL is blank, so code-server's Claude Code and opencode don't know qmd exists" \
         "Set EXIST_SEARCH_MCP_URL=http://qmd:8181/mcp in .env.shared, then: docker compose up -d --force-recreate code-server"
else
    ok "clients point at ${EXIST_SEARCH_MCP_URL}"
fi

finish
