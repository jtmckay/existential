#!/usr/bin/env bash
# ollama-pull — pull an Ollama model or create one from a Modelfile via HTTP API.
# Used by ollama-decree migrations; idempotent on both pull and create.
#
# Naming a model by ROLE (preferred):
#   OLLAMA_ROLE      chat | chat-ctx | extract | embed | vision
#
# The role resolves to the matching EXIST_MODEL_* global from .env.shared, which
# ai/ollama/docker-compose.yml passes through to this sidecar. That keeps the
# model choice in ONE place — see the "Model Selection" block in
# .env.exist.shared — instead of hardcoded in each migration:
#
#   chat      → EXIST_MODEL_CHAT
#   chat-ctx  → rebuilds EXIST_MODEL_CHAT with num_ctx=EXIST_MODEL_CHAT_NUM_CTX,
#               keeping the same tag so every consumer still names one model
#   extract   → EXIST_MODEL_EXTRACT
#   embed     → EXIST_MODEL_EMBED
#   vision    → EXIST_MODEL_VISION
#
# A role that resolves to an EMPTY value is skipped, not an error: that is how
# EXIST_MODEL_VISION= turns the vision model off on a small card.
#
# Naming a model directly (still supported):
#   OLLAMA_MODEL     model tag  e.g. "gemma4:e2b-it-qat", "bge-m3:latest"
#   OLLAMA_URL       API base (default: http://ollama:11434)
#
# Create with a Modelfile (optional — replaces pull with /api/create):
#   OLLAMA_FROM      base model  e.g. "gemma4:e2b-it-qat"
#   OLLAMA_NUM_CTX   override num_ctx  e.g. "32768"
#
# When OLLAMA_FROM is set, the routine calls /api/create to build a model
# named OLLAMA_MODEL from OLLAMA_FROM with any supplied Modelfile params.

set -euo pipefail

OLLAMA_ROLE="${OLLAMA_ROLE:-}"

# Resolve a role to its EXIST_MODEL_* global. Runs before the pre-check so an
# unknown role fails the same way in both paths.
if [ -n "$OLLAMA_ROLE" ]; then
    case "$OLLAMA_ROLE" in
        chat)     OLLAMA_MODEL="${EXIST_MODEL_CHAT:-}" ;;
        extract)  OLLAMA_MODEL="${EXIST_MODEL_EXTRACT:-}" ;;
        embed)    OLLAMA_MODEL="${EXIST_MODEL_EMBED:-}" ;;
        vision)   OLLAMA_MODEL="${EXIST_MODEL_VISION:-}" ;;
        chat-ctx)
            OLLAMA_MODEL="${EXIST_MODEL_CHAT:-}"
            OLLAMA_FROM="${EXIST_MODEL_CHAT:-}"
            OLLAMA_NUM_CTX="${EXIST_MODEL_CHAT_NUM_CTX:-}"
            ;;
        *)
            echo "Unknown OLLAMA_ROLE '${OLLAMA_ROLE}' (chat|chat-ctx|extract|embed|vision)" >&2
            exit 1
            ;;
    esac
    if [ -z "$OLLAMA_MODEL" ]; then
        echo "OLLAMA_ROLE=${OLLAMA_ROLE} resolves to an empty model — skipping."
        exit 0
    fi
fi

if [ "${DECREE_PRE_CHECK:-}" = "true" ]; then
    source "$(dirname "${BASH_SOURCE[0]}")/../lib/precheck.sh"
    command -v curl >/dev/null 2>&1 || precheck_fail "ollama-pull" "curl not found"
    command -v jq   >/dev/null 2>&1 || precheck_fail "ollama-pull" "jq not found"
    [ -n "${OLLAMA_MODEL:-}" ] || precheck_fail "ollama-pull" "OLLAMA_MODEL or OLLAMA_ROLE is required"
    precheck_pass "ollama-pull"
    exit 0
fi

OLLAMA_URL="${OLLAMA_URL:-http://ollama:11434}"
OLLAMA_MODEL="${OLLAMA_MODEL:?OLLAMA_MODEL or OLLAMA_ROLE is required}"
OLLAMA_FROM="${OLLAMA_FROM:-}"
OLLAMA_NUM_CTX="${OLLAMA_NUM_CTX:-}"

# ── Helpers ───────────────────────────────────────────────────────────────────

ollama_api() {
    curl -fsSL --max-time 30 "${OLLAMA_URL}${1}" "${@:2}"
}

# Present if any installed tag shares this model's base name (before the colon),
# so "gemma4:e2b-it-qat" matches an existing "gemma4:e2b-it-qat" without demanding an exact tag.
model_present() {
    local model="$1"
    ollama_api /api/tags 2>/dev/null \
        | jq -e --arg t "$model" '
            ($t | split(":")[0]) as $base
            | [.models[]?.name] | any(. == $t or (split(":")[0] == $base))
          ' >/dev/null 2>&1
}

model_num_ctx() {
    local model="$1"
    ollama_api /api/show -d "{\"name\":\"${model}\"}" 2>/dev/null \
        | jq -r '(.parameters // "")
                 | split("\n")
                 | map(split(" ") | map(select(. != "")))
                 | map(select(length == 2 and .[0] == "num_ctx"))
                 | (.[0][1] // "0")' 2>/dev/null || echo "0"
}

stream_until_done() {
    # Ollama /api/pull and /api/create stream NDJSON.
    # Print each distinct status; exit non-zero on the first line carrying an error.
    local last_status="" line status err
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        err=$(printf '%s' "$line" | jq -r '.error // empty' 2>/dev/null || true)
        if [ -n "$err" ]; then
            echo "  ERROR: $err" >&2
            return 1
        fi
        status=$(printf '%s' "$line" | jq -r '.status // empty' 2>/dev/null || true)
        if [ -n "$status" ] && [ "$status" != "$last_status" ]; then
            echo "  $status"
            last_status="$status"
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

    # Idempotency: skip if model already exists with correct num_ctx
    if [ -n "$OLLAMA_NUM_CTX" ] && model_present "$OLLAMA_MODEL"; then
        current_ctx=$(model_num_ctx "$OLLAMA_MODEL")
        if [ "$current_ctx" = "$OLLAMA_NUM_CTX" ]; then
            echo "${OLLAMA_MODEL} already exists with num_ctx=${OLLAMA_NUM_CTX} — skipping."
            exit 0
        fi
        echo "${OLLAMA_MODEL} exists but num_ctx=${current_ctx} (want ${OLLAMA_NUM_CTX}) — recreating."
    fi

    # /api/create needs the base model present first — a bare tag that was never
    # pulled makes it fail. The chat-ctx role runs after the chat role for this
    # reason; pull here too so a direct OLLAMA_FROM call is self-sufficient.
    if ! model_present "$OLLAMA_FROM"; then
        echo "Base model ${OLLAMA_FROM} not present — pulling first..."
        jq -nc --arg m "$OLLAMA_FROM" '{model: $m}' \
            | ollama_api /api/pull -X POST -H "Content-Type: application/json" --data @- \
            | stream_until_done
    fi

    # Payload shape: ollama replaced the flat `modelfile` string with structured
    # fields (`from` plus `parameters`/`system`/…). Sending the old form to a
    # current ollama (0.32.x here) is a hard 400, which stopped this migration —
    # and, because a failed migration halts the chain, silently prevented the
    # embed/extract/vision models behind it from ever being pulled.
    echo "Creating ${OLLAMA_MODEL} from ${OLLAMA_FROM} (num_ctx=${OLLAMA_NUM_CTX:-default})..."
    if [ -n "$OLLAMA_NUM_CTX" ]; then
        jq -nc --arg m "$OLLAMA_MODEL" --arg f "$OLLAMA_FROM" --argjson c "$OLLAMA_NUM_CTX" \
            '{model: $m, from: $f, parameters: {num_ctx: $c}}'
    else
        jq -nc --arg m "$OLLAMA_MODEL" --arg f "$OLLAMA_FROM" '{model: $m, from: $f}'
    fi \
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
jq -nc --arg m "$OLLAMA_MODEL" '{model: $m}' \
    | ollama_api /api/pull -X POST -H "Content-Type: application/json" --data @- \
    | stream_until_done

echo "${OLLAMA_MODEL} pulled."
