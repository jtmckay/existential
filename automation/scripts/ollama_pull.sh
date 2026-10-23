#!/usr/bin/env bash
# ollama_pull — pull an Ollama model or create one from a Modelfile via HTTP API.
# Used by the decree daemon's ollama migrations; idempotent on pull and create.
# Every OLLAMA_* below is a param (DECREE_DATA_OLLAMA_*), all optional.
#
# Pulling is ollama's own API, so this is a no-op unless EXIST_IS_AI_OLLAMA is
# true: a llama.cpp (or any other /v1) server loads its models itself.
#
# Naming a model by ROLE (preferred):
#   OLLAMA_ROLE      chat | chat-ctx | extract | embed | vision
#
# A role resolves BOTH halves of "which model, on which machine": the tag from
# the EXIST_MODEL_* globals, and the endpoint through lib/model.sh's model_url.
# That matters as soon as roles are split across boxes — pulling the chat model
# to the embedding host would fill the wrong disk and leave chat with no model
# at all. Model choice stays in ONE place — the "Model Selection" and "Model
# Endpoints" blocks in .env.exist.shared — instead of hardcoded per migration:
#
#   chat      → EXIST_MODEL_CHAT
#   chat-ctx  → rebuilds EXIST_MODEL_CHAT with num_ctx=EXIST_MODEL_CHAT_NUM_CTX,
#               keeping the same tag so every consumer still names one model
#   extract   → EXIST_MODEL_EXTRACT
#   embed     → EXIST_MODEL_EMBED
#   vision    → EXIST_MODEL_VISION
#
# An explicit OLLAMA_URL param in the migration wins over the role's endpoint.
#
# A role that resolves to an EMPTY value is skipped, not an error: that is how
# EXIST_MODEL_VISION= turns the vision model off on a small card.
#
# Naming a model directly (still supported):
#   OLLAMA_MODEL     model tag  e.g. "gemma4:e2b-it-qat", "bge-m3:latest"
#   OLLAMA_URL       ollama's root (default: the role's endpoint without /v1)
#
# Create with a Modelfile (optional — replaces pull with /api/create):
#   OLLAMA_FROM      base model  e.g. "gemma4:e2b-it-qat"
#   OLLAMA_NUM_CTX   override num_ctx  e.g. "32768"
#
# When OLLAMA_FROM is set, the script calls /api/create to build a model
# named OLLAMA_MODEL from OLLAMA_FROM with any supplied Modelfile params.

set -euo pipefail

if [ "${EXIST_IS_AI_OLLAMA:-false}" != "true" ]; then
    echo "ollama is not enabled (EXIST_IS_AI_OLLAMA) — nothing to pull."
    exit 0
fi

# shellcheck source=../lib/model.sh
source "${DECREE_LIB}/model.sh"

OLLAMA_ROLE="$DECREE_DATA_OLLAMA_ROLE"
OLLAMA_MODEL="$DECREE_DATA_OLLAMA_MODEL"
OLLAMA_FROM="$DECREE_DATA_OLLAMA_FROM"
OLLAMA_NUM_CTX="$DECREE_DATA_OLLAMA_NUM_CTX"

if [ -n "$OLLAMA_ROLE" ]; then
    OLLAMA_MODEL="$(model_tag "$OLLAMA_ROLE")" || {
        echo "Unknown OLLAMA_ROLE '${OLLAMA_ROLE}' (chat|chat-ctx|extract|embed|vision)" >&2
        exit 1
    }
    if [ "$OLLAMA_ROLE" = chat-ctx ]; then
        OLLAMA_FROM="$OLLAMA_MODEL"
        OLLAMA_NUM_CTX="${EXIST_MODEL_CHAT_NUM_CTX:-}"
    fi
    if [ -z "$OLLAMA_MODEL" ]; then
        echo "OLLAMA_ROLE=${OLLAMA_ROLE} resolves to an empty model — skipping."
        exit 0
    fi
fi

# Precedence: an explicit OLLAMA_URL in the migration, then the role's endpoint
# (chat when no role is named). The role sits first otherwise so splitting roles
# across machines needs no migration edits, while a migration that names a host
# still gets the host it named.
OLLAMA_URL="${DECREE_DATA_OLLAMA_URL:-$(model_url "${OLLAMA_ROLE:-chat}")}"
OLLAMA_URL="${OLLAMA_URL%/}"
OLLAMA_URL="${OLLAMA_URL%/v1}"
OLLAMA_MODEL="${OLLAMA_MODEL:?OLLAMA_MODEL or OLLAMA_ROLE is required}"

# ── Helpers ───────────────────────────────────────────────────────────────────

ollama_api() {
    curl -fsSL --max-time 30 "${OLLAMA_URL}${1}" "${@:2}"
}

# /api/pull and /api/create stream for as long as the transfer takes — minutes
# for a multi-GB tag. ollama_api's 30s cap is right for /api/tags and /api/show
# and fatal here: curl exits 28 mid-stream, pipefail turns that into a routine
# failure, and a failed migration halts the queue, so the extract/embed/vision
# models behind it are never pulled either. That is the "ollama came up with no
# models" failure the e2e harness found. Mirrors exist.pull-models.sh.
ollama_api_stream() {
    curl -fsSL --no-buffer --max-time 3600 "${OLLAMA_URL}${1}" "${@:2}"
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
#
# On a fresh install this is the first migration, run the moment the daemon
# starts, so ollama may still be booting. Ten minutes, then fail: a failed
# migration blocks the rest until `decree process --retry`.

echo "Waiting for ollama at ${OLLAMA_URL}..."
for i in $(seq 1 120); do
    if ollama_api /api/tags >/dev/null 2>&1; then
        echo "ollama ready."
        break
    fi
    [ "$i" -eq 120 ] && { echo "ollama did not respond within 10 minutes" >&2; exit 1; }
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
            | ollama_api_stream /api/pull -X POST -H "Content-Type: application/json" --data @- \
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
        | ollama_api_stream /api/create -X POST -H "Content-Type: application/json" --data @- \
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
    | ollama_api_stream /api/pull -X POST -H "Content-Type: application/json" --data @- \
    | stream_until_done

echo "${OLLAMA_MODEL} pulled."
