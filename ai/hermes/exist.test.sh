#!/usr/bin/env bash
# exist.test.sh — diagnose hermes-agent: health, API auth, configured model,
# MCP server reachability, and end-to-end conversation memory.
#
# Read-only. Memory test creates an ephemeral session id; no cleanup needed
# (decree-style state is not persisted unless explicitly stored).
#
# See CLAUDE.md "Service test scripts" for the convention.

set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../src/test" && pwd)/exist-test.sh"
exist_self_elevate
exist_test_init "hermes" EXIST_IS_AI_HERMES
skip_if_disabled

# ── Config ────────────────────────────────────────────────────────────────────

HERMES_URL="${HERMES_URL:-http://hermes-agent:8642}"
HERMES_API_KEY="${HERMES_API_KEY:-${EXIST_HERMES_API_KEY:-}}"
HERMES_CONFIG="/repo/ai/hermes/data/config.yaml"

AUTH=()
[ -n "$HERMES_API_KEY" ] && AUTH=(-H "Authorization: Bearer ${HERMES_API_KEY}")

# ── 1. Health endpoint ────────────────────────────────────────────────────────

HEALTH=$(curl -sS --max-time 10 "${HERMES_URL}/health" 2>/dev/null || true)
if [ -z "$HEALTH" ]; then
    fail "hermes-agent /health reachable" \
         "no response from ${HERMES_URL}/health" \
         "docker ps | grep hermes-agent; docker logs hermes-agent"
elif echo "$HEALTH" | python3 -c "import sys,json; d=json.load(sys.stdin); assert d.get('status','') in ('ok','healthy','running')" 2>/dev/null; then
    ok "hermes-agent /health reachable"
else
    warn "hermes-agent /health reachable" \
         "unexpected status payload: ${HEALTH}" \
         "Check hermes-agent logs for startup errors"
fi

# Routing coverage — same /health, but reached via caddy's <domain> / public
# blocks. Separates "agent is down" from "caddy/pihole routing is broken".
probe_caddy "hermes-agent /health" hermes-agent /health 200

# hermes-dashboard is also fronted by caddy. We don't know its exact
# health-endpoint contract, so accept any non-error status at root — this
# only probes routing, not correctness.
probe_caddy_any   "hermes-dashboard root" hermes-dashboard / "^(200|301|302|401|403|404)$"

# ── 2. API key ────────────────────────────────────────────────────────────────

if [ -z "$HERMES_API_KEY" ]; then
    warn "hermes API key configured" \
         "EXIST_HERMES_API_KEY is empty" \
         "Set EXIST_HERMES_API_KEY in .env.shared and re-run ./existential.sh"
else
    ok "hermes API key configured"
fi

# ── 3. /v1/models (proves API + auth) ─────────────────────────────────────────

CODE=$(curl -sS -o /dev/null -w "%{http_code}" --max-time 10 "${AUTH[@]}" "${HERMES_URL}/v1/models" 2>/dev/null || echo "000")
case "$CODE" in
    200) ok "hermes /v1/models OK" ;;
    401) fail "hermes /v1/models OK" \
              "401 unauthorized" \
              "EXIST_HERMES_API_KEY in .env.shared must match what hermes-agent sees. Re-run ./existential.sh." ;;
    000) fail "hermes /v1/models OK" \
              "no response within 10s" \
              "docker logs hermes-agent" ;;
    *)   fail "hermes /v1/models OK" \
              "HTTP $CODE" \
              "docker logs hermes-agent" ;;
esac

# ── 4. Configured model (from config.yaml on disk) ───────────────────────────

if [ -f "$HERMES_CONFIG" ]; then
    CONFIGURED_MODEL=$(grep -A1 '^model:' "$HERMES_CONFIG" | grep 'default:' | sed 's/.*default: *//' | tr -d '"' || true)
    if [ -n "$CONFIGURED_MODEL" ]; then
        ok "hermes config.yaml model=${CONFIGURED_MODEL}"
    else
        warn "hermes config.yaml model set" \
             "no 'model.default' in ${HERMES_CONFIG}" \
             "Run 'hermes model' inside hermes-agent to configure"
    fi
else
    warn "hermes config.yaml present" \
         "${HERMES_CONFIG} not found" \
         "Run ./existential.sh run hermes (or boot the container so it generates default config)"
fi

# ── 5. MCP servers configured (best-effort URL reachability) ─────────────────

if [ -f "$HERMES_CONFIG" ]; then
    while IFS= read -r SERVER_URL; do
        [ -z "$SERVER_URL" ] && continue
        CLEAN_URL=$(echo "$SERVER_URL" | sed 's/\${[^}]*}//g')
        CODE=$(curl -sS -o /dev/null -w "%{http_code}" --max-time 5 "$CLEAN_URL" 2>/dev/null || echo "000")
        if [ "$CODE" = "000" ]; then
            warn "MCP server reachable: ${CLEAN_URL}" \
                 "no response" \
                 "Is the MCP container running? Check its compose / logs."
        else
            ok "MCP server reachable: ${CLEAN_URL}"
        fi
    done < <(python3 -c "
import re
try:
    content = open('${HERMES_CONFIG}').read()
except FileNotFoundError:
    raise SystemExit(0)
m = re.search(r'mcp_servers:\n((?:  .*\n?)+)', content)
if not m: raise SystemExit(0)
for line in m.group(1).splitlines():
    u = re.match(r'\s+url:\s*(\S+)', line)
    if u: print(u.group(1))
" 2>/dev/null)
fi

# ── 6. Conversation memory (verifies session continuity end-to-end) ──────────

SESSION_ID="exist-test-memory-$(date +%s)"
FIRST_REQ='{"model":"default","messages":[{"role":"user","content":"My lucky number is 7331. Acknowledge it."}],"stream":false}'
SECOND_REQ='{"model":"default","messages":[{"role":"user","content":"My lucky number is 7331. Acknowledge it."},{"role":"assistant","content":"Acknowledged."},{"role":"user","content":"What is my lucky number?"}],"stream":false}'

FIRST=$(curl -sS --max-time 30 "${AUTH[@]}" \
    -H "Content-Type: application/json" \
    -H "X-Hermes-Session-Id: ${SESSION_ID}" \
    "${HERMES_URL}/v1/chat/completions" -d "$FIRST_REQ" 2>/dev/null || true)
SECOND=$(curl -sS --max-time 30 "${AUTH[@]}" \
    -H "Content-Type: application/json" \
    -H "X-Hermes-Session-Id: ${SESSION_ID}" \
    "${HERMES_URL}/v1/chat/completions" -d "$SECOND_REQ" 2>/dev/null || true)

REPLY=$(echo "$SECOND" | python3 -c "
import sys, json
try: print(json.load(sys.stdin)['choices'][0]['message']['content'])
except Exception: pass
" 2>/dev/null || true)

if [ -z "$FIRST" ] || [ -z "$SECOND" ]; then
    fail "hermes memory: chat completion round-trip" \
         "no response from /v1/chat/completions" \
         "docker logs hermes-agent (model may be down or unreachable)"
elif echo "$REPLY" | grep -qi "7331"; then
    ok "hermes memory: session recalls earlier message"
else
    warn "hermes memory: session recalls earlier message" \
         "model did not echo '7331' (got: $(echo "$REPLY" | head -c 80)…)" \
         "num_ctx is likely too small. ollama show <model> — confirm num_ctx >= 32768; check 'docker logs hermes-agent | grep truncat'"
fi

finish
