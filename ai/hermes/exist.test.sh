#!/usr/bin/env bash
# exist.test.sh — diagnose hermes-agent: health, API auth, configured model,
# MCP server reachability, and end-to-end conversation memory.
#
# Read-only. Memory test creates an ephemeral session id; no cleanup needed
# (decree-style state is not persisted unless explicitly stored).
#
# See .claude/reference/testing.md for the convention.

set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../src/test" && pwd)/exist-test.sh"
exist_self_elevate
exist_test_init "hermes" EXIST_IS_AI_HERMES
skip_if_disabled

# ── Config ────────────────────────────────────────────────────────────────────

HERMES_URL="${HERMES_URL:-http://hermes-agent:8642}"
HERMES_API_KEY="${HERMES_API_KEY:-${EXIST_HERMES_API_KEY:-}}"
# Seeded by exist.initial.sh and then owned by hermes; /opt/data in the
# container is volumes/hermes_agent_data on the host.
HERMES_CONFIG="/repo/volumes/hermes_agent_data/config.yaml"

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
# Hostname is hermes-agent-dashboard, not hermes-dashboard — the Caddyfile is
# the source of truth for which hostnames exist, and it defines
# hermes-agent-dashboard.{$CADDY_DOMAIN} -> hermes-agent:9119.
probe_caddy_any   "hermes-dashboard root" hermes-agent-dashboard / "^(200|301|302|401|403|404)$"

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
    # Scope to the model: block — the shipped config is ~1900 lines and carries
    # comment lines between `model:` and `default:`, so a fixed -A window misses it.
    CONFIGURED_MODEL=$(awk '/^model:/ { f = 1; next } f && /^[^[:space:]#]/ { exit } f' "$HERMES_CONFIG" \
        | grep -m1 -E '^[[:space:]]*default:' | sed 's/.*default: *//' | tr -d '"' || true)
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

# ── 4b. Context window (config.yaml vs the model ollama actually built) ──────
#
# Hermes packs its prompt to config.yaml's context_length, and ollama truncates
# the overflow SILENTLY — no error, the agent just starts forgetting its
# instructions. Nothing else in the stack reports this, and section 6's memory
# probe only catches it after the fact and only sometimes, so check it directly.
#
# Two comparisons, in order of authority:
#   1. vs ollama's real num_ctx for this model — exceeding it IS the truncation,
#      so that fails.
#   2. vs the 64k hermes needs, and vs EXIST_MODEL_CHAT_NUM_CTX — degraded or
#      drifted, but working, so those warn. `./existential.sh` reconciles the
#      drift on its next run (ai/hermes/exist.initial.sh).
HERMES_CTX_FLOOR=65536

if [ -f "$HERMES_CONFIG" ]; then
    load_env_exist
    CFG_CTX=$(grep -m1 -E '^[[:space:]]*context_length:' "$HERMES_CONFIG" | grep -oE '[0-9]+' || true)
    WANT_CTX="${EXIST_MODEL_CHAT_NUM_CTX:-}"

    if [ -z "$CFG_CTX" ]; then
        warn "hermes context_length set" \
             "no context_length in ${HERMES_CONFIG}" \
             "./existential.sh  (exist.initial.sh writes it from EXIST_MODEL_CHAT_NUM_CTX)"
    else
        # The real ceiling. Two sources, and the order matters:
        #
        #   /api/ps    what the LOADED instance actually allocated. Authoritative,
        #              because a tag with no baked num_ctx silently inherits
        #              ollama's server default (4096) — which is invisible in
        #              /api/show and is the exact state that truncates hermes.
        #   /api/show  the Modelfile's baked num_ctx. Used when the model is not
        #              currently loaded, so the check still works cold.
        OLLAMA_API="${OLLAMA_URL:-${EXIST_OLLAMA_URL:-http://ollama:11434}}"
        REAL_CTX=""
        REAL_SRC=""
        if [ -n "${CONFIGURED_MODEL:-}" ]; then
            REAL_CTX=$(curl -sS --max-time 5 "${OLLAMA_API}/api/ps" 2>/dev/null | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    want = sys.argv[1]
    for m in d.get('models', []):
        if m.get('model') == want or m.get('name') == want:
            print(m.get('context_length') or ''); break
    else: print('')
except Exception: print('')
" "$CONFIGURED_MODEL" 2>/dev/null || true)
            [ -n "$REAL_CTX" ] && REAL_SRC="loaded"

            if [ -z "$REAL_CTX" ]; then
                REAL_CTX=$(curl -sS --max-time 5 "${OLLAMA_API}/api/show" \
                            -d "{\"name\":\"${CONFIGURED_MODEL}\"}" 2>/dev/null | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    for line in d.get('parameters','').splitlines():
        p = line.split()
        if len(p)==2 and p[0]=='num_ctx': print(p[1]); break
    else: print('')
except Exception: print('')
" 2>/dev/null || true)
                [ -n "$REAL_CTX" ] && REAL_SRC="Modelfile"
            fi
        fi

        if [ -n "$REAL_CTX" ] && [ "$CFG_CTX" -gt "$REAL_CTX" ]; then
            fail "hermes context_length <= ollama context" \
                 "config.yaml says ${CFG_CTX} but ${CONFIGURED_MODEL} (${REAL_SRC}) gives ${REAL_CTX} — every prompt above ${REAL_CTX} tokens is truncated silently" \
                 "./existential.sh run ollama pull-models   (bakes num_ctx=${WANT_CTX:-EXIST_MODEL_CHAT_NUM_CTX} into the tag), then: docker exec ollama ollama stop ${CONFIGURED_MODEL}"
        elif [ "$CFG_CTX" -lt "$HERMES_CTX_FLOOR" ]; then
            warn "hermes context_length >= ${HERMES_CTX_FLOOR}" \
                 "config.yaml says ${CFG_CTX}; hermes needs ${HERMES_CTX_FLOOR} for skills + memory + tool definitions" \
                 "Raise EXIST_MODEL_CHAT_NUM_CTX in .env.shared, then ./existential.sh && ./existential.sh run ollama pull-models"
        elif [ -n "$WANT_CTX" ] && [ "$CFG_CTX" != "$WANT_CTX" ]; then
            warn "hermes context_length matches EXIST_MODEL_CHAT_NUM_CTX" \
                 "config.yaml says ${CFG_CTX}, .env.shared says ${WANT_CTX}" \
                 "./existential.sh   (reconciles context_length on the next run)"
        else
            ok "hermes context_length=${CFG_CTX}${REAL_CTX:+ (ollama ${REAL_SRC}: ${REAL_CTX})}"
        fi
    fi
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

# ── 5b. Honcho memory provider (seeded by exist.initial.sh) ──────────────────
#
# Hermes needs BOTH halves to use honcho: honcho.json (connection + identity)
# and memory.provider in config.yaml (the activation key). With only the first
# it silently falls back to built-in memory — `hermes memory status` is the
# only place that difference shows.

if [ "${EXIST_IS_AI_HONCHO:-false}" = "true" ]; then
    HONCHO_JSON="/repo/volumes/hermes_agent_data/honcho.json"
    MEM_PROVIDER=$(awk '/^memory:/ { f = 1; next } f && /^[^[:space:]#]/ { exit } f' "$HERMES_CONFIG" 2>/dev/null \
        | grep -m1 -E '^[[:space:]]*provider:' | sed 's/.*provider: *//' | tr -d '"' || true)

    if [ ! -f "$HONCHO_JSON" ]; then
        warn "hermes honcho.json present" \
             "${HONCHO_JSON} not found" \
             "./existential.sh run hermes   (seeds it)"
    elif [ "$MEM_PROVIDER" != "honcho" ]; then
        warn "hermes memory provider = honcho" \
             "config.yaml memory.provider is '${MEM_PROVIDER:-unset}' — hermes is on built-in memory only" \
             "./existential.sh run hermes, or: docker exec -it hermes-agent hermes memory setup honcho"
    else
        ok "hermes memory provider = honcho"
    fi
fi

# ── 6. Conversation memory (verifies session continuity end-to-end) ──────────

# 120s, not the usual few seconds: hermes packs a ~20k-token system prompt
# (skills + memory + tool definitions) and ollama may have to load the model
# cold — a warm local run measures ~45s.
# Two real ~20k-token inferences. Warm on a GPU that is ~45s; on a CPU-only box
# it is minutes, so both curls burn their 120s and the check reports "no
# response" -- a timeout dressed up as a broken hermes. EXIST_VRAM_GB=0 is the
# stack's own record that there is no GPU (e2e's fixture sets it, so does the
# "No GPU" answer in quest), so say so and stop rather than cry wolf every tick.
if [ "${EXIST_VRAM_GB:-}" = "0" ]; then
    skip "hermes memory: chat completion round-trip" \
         "no GPU (EXIST_VRAM_GB=0) - two ~20k-token inferences would time out"
    finish
fi

SESSION_ID="exist-test-memory-$(date +%s)"
FIRST_REQ='{"model":"default","messages":[{"role":"user","content":"My lucky number is 7331. Acknowledge it."}],"stream":false}'
SECOND_REQ='{"model":"default","messages":[{"role":"user","content":"My lucky number is 7331. Acknowledge it."},{"role":"assistant","content":"Acknowledged."},{"role":"user","content":"What is my lucky number?"}],"stream":false}'

FIRST=$(curl -sS --max-time 120 "${AUTH[@]}" \
    -H "Content-Type: application/json" \
    -H "X-Hermes-Session-Id: ${SESSION_ID}" \
    "${HERMES_URL}/v1/chat/completions" -d "$FIRST_REQ" 2>/dev/null || true)
SECOND=$(curl -sS --max-time 120 "${AUTH[@]}" \
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
         "num_ctx is likely too small. ollama show <model> — confirm num_ctx >= 65536; check 'docker logs hermes-agent | grep truncat'"
fi

finish
