#!/usr/bin/env bash
# model-endpoints.sh — resolve a model ROLE to the endpoint that serves it.
#
# SOURCED ONLY. Never run directly.
#
#   source "${SCRIPT_DIR}/../utils/model-endpoints.sh"
#   url="$(endpoint_for chat)"     # an OpenAI-compatible base URL, ending /v1
#
# Every model role can sit on a different machine, so VRAM can be spread across
# boxes: chat on the 24 GB card, embeddings on the 8 GB one, vision on whatever
# is idle. Each role has its own EXIST_MODEL_URL_<ROLE> key in .env.shared, and
# each ships BLANK — blank means "wherever EXIST_MODEL_URL points".
#
# The value is whatever serves OpenAI's /v1 — ollama or llama.cpp alike. Only
# ollama's own API (/api/pull, /api/show, /api/ps) lives at the root, so the
# ollama-only callers ask ollama_root_for instead.
#
# This is the single source of truth for that fallback. Consumers ask for a role
# and never read the per-role keys themselves, so there is one place to change
# when a role is added and no consumer can disagree about the default.
# automation/lib/model.sh is the same rule inside the decree container, which
# cannot see src/; test-model-endpoints.sh asserts the two agree.
#
#   chat | chat-ctx  → EXIST_MODEL_URL_CHAT
#   extract          → EXIST_MODEL_URL_EXTRACT
#   embed            → EXIST_MODEL_URL_EMBED
#   vision           → EXIST_MODEL_URL_VISION
#
# Speech-to-text and text-to-speech are NOT here: wyoming-whisper and
# wyoming-piper run on CPU by design, so moving them frees no VRAM.

# endpoint_for <role> → the URL serving that role, on stdout.
# An unknown role is a caller bug, not a config problem: fail loudly rather than
# silently handing back the default and sending traffic to the wrong box.
endpoint_for() {
    local role="${1:-}" specific=""
    local fallback="${EXIST_MODEL_URL:-http://ollama:11434/v1}"

    case "$role" in
        chat|chat-ctx) specific="${EXIST_MODEL_URL_CHAT:-}" ;;
        extract)       specific="${EXIST_MODEL_URL_EXTRACT:-}" ;;
        embed)         specific="${EXIST_MODEL_URL_EMBED:-}" ;;
        vision)        specific="${EXIST_MODEL_URL_VISION:-}" ;;
        *)
            echo "endpoint_for: unknown role '${role}' (chat|chat-ctx|extract|embed|vision)" >&2
            return 1
            ;;
    esac

    printf '%s\n' "${specific:-$fallback}"
}

# True when every role resolves to the same place — i.e. this is a single-box
# install. Callers use it to keep their output honest: there is no point telling
# someone which box a role landed on when there is only one.
endpoints_are_uniform() {
    local first role
    first="$(endpoint_for chat)" || return 1
    for role in extract embed vision; do
        [ "$(endpoint_for "$role")" = "$first" ] || return 1
    done
    return 0
}

# ollama_root_for <role> → that role's endpoint without /v1: where ollama's own
# API (/api/pull, /api/show, /api/ps) lives. Only meaningful when ollama is what
# serves the role, so callers check EXIST_IS_AI_OLLAMA first.
ollama_root_for() {
    local url
    url="$(endpoint_for "$1")" || return 1
    url="${url%/}"
    printf '%s\n' "${url%/v1}"
}
