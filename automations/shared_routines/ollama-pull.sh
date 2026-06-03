#!/usr/bin/env bash
# ollama-pull — pull an Ollama model or create one from a Modelfile via HTTP API.
# Used by ollama-decree migrations; idempotent on both pull and create.
#
# Pull a model (required):
#   OLLAMA_MODEL     model tag  e.g. "gemma4:26b", "bge-m3:latest"
#   OLLAMA_URL       API base (default: http://ollama:11434)
#
# Create with a Modelfile (optional — replaces pull with /api/create):
#   OLLAMA_FROM      base model  e.g. "gemma4:26b"
#   OLLAMA_NUM_CTX   override num_ctx  e.g. "65536"
#
# When OLLAMA_FROM is set, the routine calls /api/create to build a model
# named OLLAMA_MODEL from OLLAMA_FROM with any supplied Modelfile params.
# This is how the extended-context gemma4:26b variant is created.

set -euo pipefail

if [ "${DECREE_PRE_CHECK:-}" = "true" ]; then
    source "$(dirname "${BASH_SOURCE[0]}")/../lib/precheck.sh"
    command -v curl >/dev/null 2>&1 || precheck_fail "ollama-pull" "curl not found"
    [ -n "${OLLAMA_MODEL:-}" ] || precheck_fail "ollama-pull" "OLLAMA_MODEL is required"
    precheck_pass "ollama-pull"
    exit 0
fi

OLLAMA_URL="${OLLAMA_URL:-http://ollama:11434}"
OLLAMA_MODEL="${OLLAMA_MODEL:?OLLAMA_MODEL is required}"
OLLAMA_FROM="${OLLAMA_FROM:-}"
OLLAMA_NUM_CTX="${OLLAMA_NUM_CTX:-}"

# ── Helpers ───────────────────────────────────────────────────────────────────

ollama_api() {
    curl -fsSL --max-time 30 "${OLLAMA_URL}${1}" "${@:2}"
}

model_present() {
    local model="$1"
    ollama_api /api/tags 2>/dev/null \
        | python3 -c "
import sys, json
tags = json.load(sys.stdin)
names = [m['name'] for m in tags.get('models', [])]
target = sys.argv[1]
found = any(n == target or n.split(':')[0] == target.split(':')[0] for n in names)
sys.exit(0 if found else 1)
" "$model" 2>/dev/null
}

model_num_ctx() {
    local model="$1"
    ollama_api /api/show -d "{\"name\":\"${model}\"}" 2>/dev/null \
        | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    for line in d.get('parameters','').splitlines():
        p = line.split()
        if len(p) == 2 and p[0] == 'num_ctx':
            print(p[1]); sys.exit(0)
    print(0)
except Exception:
    print(0)
" 2>/dev/null || echo "0"
}

stream_until_done() {
    # Ollama /api/pull and /api/create stream NDJSON.
    # Print progress dots; exit non-zero if any line has error/status=error.
    local last_status=""
    while IFS= read -r line; do
        status=$(echo "$line" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(d.get('status',''))" 2>/dev/null || true)
        if echo "$line" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); sys.exit(0 if not d.get('error') else 1)" 2>/dev/null; then
            if [ "$status" != "$last_status" ] && [ -n "$status" ]; then
                echo "  $status"
                last_status="$status"
            fi
        else
            err=$(echo "$line" | python3 -c "import sys,json; print(json.loads(sys.stdin.read()).get('error','unknown error'))" 2>/dev/null || echo "unknown error")
            echo "  ERROR: $err" >&2
            return 1
        fi
    done
}

# ── Wait for ollama to be ready ───────────────────────────────────────────────

echo "Waiting for ollama at ${OLLAMA_URL}..."
for i in $(seq 1 30); do
    if ollama_api /api/tags >/dev/null 2>&1; then
        echo "ollama ready."
        break
    fi
    [ "$i" -eq 30 ] && { echo "ollama did not respond after 30 attempts" >&2; exit 1; }
    sleep 5
done

# ── Create from Modelfile (if OLLAMA_FROM is set) ─────────────────────────────

if [ -n "$OLLAMA_FROM" ]; then
    modelfile="FROM ${OLLAMA_FROM}"
    [ -n "$OLLAMA_NUM_CTX" ] && modelfile="${modelfile}\nPARAMETER num_ctx ${OLLAMA_NUM_CTX}"

    # Idempotency: skip if model already exists with correct num_ctx
    if [ -n "$OLLAMA_NUM_CTX" ] && model_present "$OLLAMA_MODEL"; then
        current_ctx=$(model_num_ctx "$OLLAMA_MODEL")
        if [ "$current_ctx" = "$OLLAMA_NUM_CTX" ]; then
            echo "${OLLAMA_MODEL} already exists with num_ctx=${OLLAMA_NUM_CTX} — skipping."
            exit 0
        fi
        echo "${OLLAMA_MODEL} exists but num_ctx=${current_ctx} (want ${OLLAMA_NUM_CTX}) — recreating."
    fi

    echo "Creating ${OLLAMA_MODEL} from ${OLLAMA_FROM} (num_ctx=${OLLAMA_NUM_CTX:-default})..."
    printf '%s' "{\"model\":\"${OLLAMA_MODEL}\",\"modelfile\":\"$(printf '%s' "$modelfile" | sed 's/"/\\"/g')\"}" \
        | ollama_api /api/create -X POST -H "Content-Type: application/json" --data @- \
        | stream_until_done
    echo "${OLLAMA_MODEL} created."
    exit 0
fi

# ── Pull model ────────────────────────────────────────────────────────────────

if model_present "$OLLAMA_MODEL"; then
    echo "${OLLAMA_MODEL} already present — skipping pull."
    exit 0
fi

echo "Pulling ${OLLAMA_MODEL}..."
printf '%s' "{\"model\":\"${OLLAMA_MODEL}\"}" \
    | ollama_api /api/pull -X POST -H "Content-Type: application/json" --data @- \
    | stream_until_done

echo "${OLLAMA_MODEL} pulled."
