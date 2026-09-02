#!/usr/bin/env bash
# exist.test.sh — validate that mcp-playwright is fully operational.
#
# See .claude/reference/testing.md for the convention.

set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../src/test" && pwd)/exist-test.sh"
exist_self_elevate
exist_test_init "mcp" EXIST_IS_AI_MCP
skip_if_disabled

MCP_URL="http://mcp-playwright:8931/mcp"
MCP_ACCEPT="Accept: application/json, text/event-stream"
MCP_CT="Content-Type: application/json"

# ── 1. Listening ─────────────────────────────────────────────────────────────
#
# The server 403s an unknown Host and 400s a non-MCP request, so any of these
# proves it is up. It proves nothing else — see check 2.

probe_service_any "mcp-playwright listening" mcp-playwright 8931 / "^(400|403)$"

# ── 2. MCP handshake ─────────────────────────────────────────────────────────

HEADERS=$(mktemp); BODY=$(mktemp)
SESSION=""
# The session outlives the request, and with it a live browser. Terminate it
# however this script exits.
cleanup() {
    if [[ -n "${SESSION}" ]]; then
        curl -sS -o /dev/null --max-time 10 -X DELETE \
            -H "mcp-session-id: ${SESSION}" "${MCP_URL}" 2>/dev/null || true
    fi
    rm -f "${HEADERS}" "${BODY}"
}
trap cleanup EXIT

curl -sS -D "${HEADERS}" -o "${BODY}" --max-time 20 -X POST "${MCP_URL}" \
    -H "${MCP_CT}" -H "${MCP_ACCEPT}" \
    -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"exist-test","version":"1"}}}' \
    2>/dev/null || true

SESSION=$(tr -d '\r' < "${HEADERS}" | sed -n 's/^[Mm][Cc][Pp]-[Ss]ession-[Ii]d:[[:space:]]*//p' | head -1)
SERVER=$(sed -n 's/^data: //p' "${BODY}" | jq -r '.result.serverInfo.name // empty' 2>/dev/null || true)

if [[ -z "${SESSION}" || -z "${SERVER}" ]]; then
    fail "mcp-playwright MCP handshake" \
         "initialize returned no session id / serverInfo (body: $(head -c 120 "${BODY}"))" \
         "docker logs mcp-playwright — check --allowed-hosts includes mcp-playwright:8931"
else
    ok "mcp-playwright MCP handshake (${SERVER})"

    curl -sS -o /dev/null --max-time 10 -X POST "${MCP_URL}" \
        -H "${MCP_CT}" -H "${MCP_ACCEPT}" -H "mcp-session-id: ${SESSION}" \
        -d '{"jsonrpc":"2.0","method":"notifications/initialized"}' 2>/dev/null || true

    # ── 3. Browser actually launches ─────────────────────────────────────────
    #
    # This is the check that matters. The server answers MCP perfectly well with
    # no browser installed; every tool call then returns "Chromium distribution
    # 'chrome' is not found". Nothing else in the stack notices — hermes just
    # reports that browsing failed.
    curl -sS -o "${BODY}" --max-time 60 -X POST "${MCP_URL}" \
        -H "${MCP_CT}" -H "${MCP_ACCEPT}" -H "mcp-session-id: ${SESSION}" \
        -d '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"browser_navigate","arguments":{"url":"about:blank"}}}' \
        2>/dev/null || true

    if sed -n 's/^data: //p' "${BODY}" | jq -e '.result.isError != true' >/dev/null 2>&1; then
        ok "mcp-playwright browser launches"
    else
        fail "mcp-playwright browser launches" \
             "$(sed -n 's/^data: //p' "${BODY}" | jq -r '.result.content[0].text // .error.message // "no result"' 2>/dev/null | head -3 | tr '\n' ' ')" \
             "The image must ship its own browser — pin mcr.microsoft.com/playwright/mcp, not node + npx @playwright/mcp"
    fi
fi

# ── 4. Caddy routing ─────────────────────────────────────────────────────────
#
# 400 is the server rejecting a plain GET, which is what proves Caddy reached it
# and that mcp-playwright.<domain> is in --allowed-hosts (an unknown Host is 403).

probe_caddy_any "mcp-playwright via caddy" mcp-playwright / "^400$"

finish
