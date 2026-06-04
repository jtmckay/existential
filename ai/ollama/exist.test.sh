#!/usr/bin/env bash
# exist.test.sh — diagnose ollama: reachability, configured model, num_ctx,
# memory headroom, and a quick generation benchmark.
#
# Read-only. /api/generate is a single prompt with num_predict=5, no state
# carried over.
#
# See CLAUDE.md "Service test scripts" for the convention.

set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../src/test" && pwd)/exist-test.sh"
exist_self_elevate
exist_test_init "ollama" EXIST_IS_AI_OLLAMA
skip_if_disabled

# ── Config ────────────────────────────────────────────────────────────────────

OLLAMA_URL="${OLLAMA_URL:-http://ollama:11434}"
MODEL="${OLLAMA_MODEL:-gemma4:26b}"

# LightRAG graph synthesis + Hermes system prompt can exceed 32k tokens.
# 32k is the hard floor; 64k is the recommended target (see Modelfile).
MIN_CTX_FAIL=32768
MIN_CTX_WARN=65536

# ── 1. Reachability ───────────────────────────────────────────────────────────

TAGS=$(curl -sS --max-time 5 "${OLLAMA_URL}/api/tags" 2>/dev/null || true)
if [ -z "$TAGS" ]; then
    fail "ollama reachable at ${OLLAMA_URL}" \
         "no response within 5s" \
         "docker ps | grep ollama; docker logs ollama"
    finish
fi
ok "ollama reachable at ${OLLAMA_URL}"

# In e2e, models are not pre-pulled — skip model-dependent checks.
[ "${E2E_MODE:-}" = "1" ] && finish

# Routing coverage — same /api/tags reached via caddy. Separates "ollama
# down" from "caddy/pihole routing broken".
probe_caddy "ollama /api/tags" ollama /api/tags 200

# ── 2. Model presence ────────────────────────────────────────────────────────

if echo "$TAGS" | python3 -c "
import sys, json
tags = json.load(sys.stdin)
names = [m['name'] for m in tags.get('models', [])]
m = sys.argv[1]
if not any(n == m or n.split(':')[0] == m.split(':')[0] for n in names):
    sys.exit(1)
" "$MODEL" 2>/dev/null; then
    ok "model '${MODEL}' present"
else
    AVAILABLE=$(echo "$TAGS" | python3 -c "import sys,json; print(', '.join(m['name'] for m in json.load(sys.stdin).get('models',[])) or 'none')" 2>/dev/null)
    fail "model '${MODEL}' present" \
         "available: ${AVAILABLE}" \
         "ollama pull ${MODEL}   (or update OLLAMA_MODEL)"
    finish
fi

# ── 3. num_ctx ────────────────────────────────────────────────────────────────

MODEL_INFO=$(curl -sS "${OLLAMA_URL}/api/show" -d "{\"name\":\"${MODEL}\"}" 2>/dev/null || true)
NUM_CTX=$(echo "$MODEL_INFO" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    for line in d.get('parameters','').splitlines():
        p = line.split()
        if len(p)==2 and p[0]=='num_ctx': print(p[1]); break
    else: print(0)
except Exception: print(0)
" 2>/dev/null || echo "0")

NUM_CTX="${NUM_CTX:-0}"
if [ "$NUM_CTX" -eq 0 ]; then
    fail "num_ctx readable for ${MODEL}" \
         "could not parse num_ctx from /api/show" \
         "ollama show ${MODEL}  (and apply ai/ollama/Modelfile)"
elif [ "$NUM_CTX" -lt "$MIN_CTX_FAIL" ]; then
    fail "num_ctx >= ${MIN_CTX_FAIL}" \
         "num_ctx=${NUM_CTX} — hermes system prompt (~18k tokens) will be truncated" \
         "Edit ai/ollama/Modelfile.exist.Modelfile: PARAMETER num_ctx ${MIN_CTX_WARN}; re-run ./existential.sh run ollama"
elif [ "$NUM_CTX" -lt "$MIN_CTX_WARN" ]; then
    warn "num_ctx >= ${MIN_CTX_WARN}" \
         "num_ctx=${NUM_CTX} — LightRAG graph synthesis may exceed this" \
         "Edit ai/ollama/Modelfile.exist.Modelfile: PARAMETER num_ctx ${MIN_CTX_WARN}; re-run ./existential.sh run ollama"
else
    ok "num_ctx=${NUM_CTX} (>= ${MIN_CTX_WARN})"
fi

# ── 4. Memory headroom ────────────────────────────────────────────────────────

AVAIL_KB=$(grep MemAvailable /proc/meminfo 2>/dev/null | awk '{print $2}' || echo 0)
AVAIL_GB=$(( AVAIL_KB / 1024 / 1024 ))
if [ "$AVAIL_KB" -gt 0 ] && [ "$NUM_CTX" -gt 0 ]; then
    # Calibrated from observed 2GB @ 4096 tokens for gemma4:26b
    KV_GB=$(( NUM_CTX / 2048 ))
    if [ "$KV_GB" -gt "$AVAIL_GB" ]; then
        warn "RAM headroom for KV cache" \
             "KV cache for num_ctx=${NUM_CTX} needs ~${KV_GB}GB, ${AVAIL_GB}GB available" \
             "Reduce num_ctx or free RAM"
    else
        ok "RAM headroom: ~${KV_GB}GB needed, ${AVAIL_GB}GB available"
    fi
fi

# ── 5. Generation benchmark ──────────────────────────────────────────────────

BENCH=$(curl -sS --max-time 60 "${OLLAMA_URL}/api/generate" \
    -d "{\"model\":\"${MODEL}\",\"prompt\":\"Reply with only the word yes.\",\"options\":{\"num_predict\":5},\"stream\":false}" 2>/dev/null || true)

if [ -z "$BENCH" ]; then
    fail "generation benchmark" \
         "no response from /api/generate within 60s" \
         "docker logs ollama; ollama ps"
else
    RATE=$(echo "$BENCH" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    ns = d.get('eval_duration', 0); n = d.get('eval_count', 0)
    print(f'{n/(ns/1e9):.1f}' if ns and n else 'unknown')
except Exception: print('unknown')
" 2>/dev/null || echo "unknown")
    ok "generation rate: ${RATE} tok/s"
fi

finish
