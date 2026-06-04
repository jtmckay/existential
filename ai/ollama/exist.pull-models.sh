#!/usr/bin/env bash
# ollama — manual model pull and Modelfile creation via HTTP API.
#
# This is a manual fallback. Under normal operation ollama-decree migrations
# handle model setup automatically after ollama passes its health check.
#
# Run manually:
#   ./existential.sh run ollama pull-models

set -euo pipefail

OLLAMA_URL="${OLLAMA_URL:-http://ollama:11434}"

MODELS=(
    gemma4:26b      # primary chat / query LLM (hermes + lightrag query)
    qwen2.5:7b      # extraction LLM (lightrag entity/relationship extraction)
    bge-m3:latest   # embedding model (lightrag vector store)
    llava:latest    # vision model (ollama-ocr, open-webui image chat)
)

hr() { printf '%0.s─' {1..56}; echo; }
die() { echo "Error: $*" >&2; exit 1; }

# ── Preflight ─────────────────────────────────────────────────────────────────

echo ""
echo "  ollama model setup"
hr
echo ""
echo "  Waiting for ollama at ${OLLAMA_URL}..."
for i in $(seq 1 30); do
    if curl -sf --max-time 5 "${OLLAMA_URL}/api/tags" >/dev/null 2>&1; then
        echo "  ollama ready."
        break
    fi
    [ "$i" -eq 30 ] && die "ollama did not respond after 30 attempts"
    sleep 5
done

# ── Pull models ───────────────────────────────────────────────────────────────

echo ""
for model in "${MODELS[@]%%#*}"; do
    model="${model%%[[:space:]]*}"
    [ -z "$model" ] && continue
    echo "  Pulling ${model}..."
    curl -fsSL --no-buffer "${OLLAMA_URL}/api/pull" \
        -d "{\"model\":\"${model}\"}" \
        | while IFS= read -r line; do
            status=$(printf '%s' "$line" | python3 -c "import sys,json; print(json.loads(sys.stdin.read()).get('status',''))" 2>/dev/null || true)
            [ -n "$status" ] && printf '\r  %-60s' "$status"
        done
    echo ""
    echo "  Pulled ${model}."
    echo ""
done

# ── Apply extended context window to gemma4:26b ───────────────────────────────
# Mirrors migration 02-create-gemma4-26b-ctx65536.md.

NUM_CTX=65536
echo "  Applying num_ctx=${NUM_CTX} to gemma4:26b via /api/create..."
curl -fsSL "${OLLAMA_URL}/api/create" \
    -d "{\"model\":\"gemma4:26b\",\"modelfile\":\"FROM gemma4:26b\\nPARAMETER num_ctx ${NUM_CTX}\"}" \
    | while IFS= read -r line; do
        status=$(printf '%s' "$line" | python3 -c "import sys,json; print(json.loads(sys.stdin.read()).get('status',''))" 2>/dev/null || true)
        [ -n "$status" ] && echo "  $status"
    done
echo "  gemma4:26b updated."

echo ""
hr
echo ""
echo "  Done. Models available:"
curl -sf "${OLLAMA_URL}/api/tags" | python3 -c "
import sys, json
for m in json.load(sys.stdin).get('models', []):
    print(f\"  {m['name']}\")
" 2>/dev/null || true
echo ""
