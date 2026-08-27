#!/usr/bin/env bash
# ollama — manual model pull, driven by the global model selection.
#
# This is a manual fallback. Under normal operation the ollama-decree
# migrations (decree/migrations.example/) do exactly this after ollama passes
# its health check — copy them into decree/migrations/ and they run once.
#
# Which models get pulled is NOT decided here: it comes from the "Model
# Selection" block in .env.shared (EXIST_MODEL_CHAT, EXIST_MODEL_EXTRACT,
# EXIST_MODEL_EMBED, EXIST_MODEL_VISION). Change it there and re-run this.
#
# Run manually:
#   ./existential.sh run ollama pull-models

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# existential.sh exports .env.shared before dispatching, but this script is also
# run directly. Source it ourselves so both paths see the same models.
if [ -f "${REPO_DIR}/.env.shared" ]; then
    set -a
    # shellcheck disable=SC1091
    . "${REPO_DIR}/.env.shared"
    set +a
fi

OLLAMA_URL="${OLLAMA_URL:-http://ollama:11434}"

MODEL_CHAT="${EXIST_MODEL_CHAT:-}"
MODEL_CHAT_NUM_CTX="${EXIST_MODEL_CHAT_NUM_CTX:-}"
MODEL_EXTRACT="${EXIST_MODEL_EXTRACT:-}"
MODEL_EMBED="${EXIST_MODEL_EMBED:-}"
MODEL_VISION="${EXIST_MODEL_VISION:-}"

hr() { printf '%0.s─' {1..56}; echo; }
die() { echo "Error: $*" >&2; exit 1; }

command -v jq >/dev/null 2>&1 || die "jq not found"
[ -n "$MODEL_CHAT" ] || die "EXIST_MODEL_CHAT is not set in ${REPO_DIR}/.env.shared"

# Roles in pull order; the chat model must land before the num_ctx rebuild.
# A blank value is skipped, which is how EXIST_MODEL_VISION= turns vision off.
declare -a MODELS=()
for m in "$MODEL_CHAT" "$MODEL_EXTRACT" "$MODEL_EMBED" "$MODEL_VISION"; do
    [ -n "$m" ] || continue
    # De-dupe: EXIST_MODEL_EXTRACT defaults to the same tag as chat.
    for seen in ${MODELS[@]+"${MODELS[@]}"}; do
        [ "$seen" = "$m" ] && { m=""; break; }
    done
    [ -n "$m" ] && MODELS+=("$m")
done

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
for model in "${MODELS[@]}"; do
    echo "  Pulling ${model}..."
    jq -nc --arg m "$model" '{model: $m}' \
        | curl -fsSL --no-buffer "${OLLAMA_URL}/api/pull" \
               -H "Content-Type: application/json" --data @- \
        | while IFS= read -r line; do
            [ -n "$line" ] || continue
            status=$(printf '%s' "$line" | jq -r '.status // empty' 2>/dev/null || true)
            [ -n "$status" ] && printf '\r  %-60s' "$status"
        done
    echo ""
    echo "  Pulled ${model}."
    echo ""
done

# ── Apply the chat context window ─────────────────────────────────────────────
# Mirrors migration 02-set-chat-context.md. The rebuilt model keeps the same
# tag, so every consumer still names exactly one model.

if [ -n "$MODEL_CHAT_NUM_CTX" ]; then
    echo "  Applying num_ctx=${MODEL_CHAT_NUM_CTX} to ${MODEL_CHAT} via /api/create..."
    jq -nc --arg m "$MODEL_CHAT" \
           --arg f "FROM ${MODEL_CHAT}"$'\n'"PARAMETER num_ctx ${MODEL_CHAT_NUM_CTX}" \
           '{model: $m, modelfile: $f}' \
        | curl -fsSL --no-buffer "${OLLAMA_URL}/api/create" \
               -H "Content-Type: application/json" --data @- \
        | while IFS= read -r line; do
            [ -n "$line" ] || continue
            status=$(printf '%s' "$line" | jq -r '.status // empty' 2>/dev/null || true)
            [ -n "$status" ] && echo "  $status"
        done
    echo "  ${MODEL_CHAT} updated."
fi

echo ""
hr
echo ""
echo "  Done. Models available:"
curl -sf "${OLLAMA_URL}/api/tags" | jq -r '.models[]?.name | "  " + .' 2>/dev/null || true
echo ""
