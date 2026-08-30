#!/usr/bin/env bash
# model-endpoints.sh — resolve a model ROLE to the endpoint that serves it.
#
# SOURCED ONLY. Never run directly.
#
#   source "${SCRIPT_DIR}/../utils/model-endpoints.sh"
#   url="$(endpoint_for chat)"
#
# Every model role can sit on a different machine, so VRAM can be spread across
# boxes: chat on the 24 GB card, embeddings on the 8 GB one, vision on whatever
# is idle. Each role has its own EXIST_OLLAMA_URL_<ROLE> key in .env.shared, and
# each ships BLANK — blank means "wherever EXIST_OLLAMA_URL points", which is
# what every install did before roles existed.
#
# This is the single source of truth for that fallback. Consumers ask for a role
# and never read the per-role keys themselves, so there is one place to change
# when a role is added and no consumer can disagree about the default.
#
# Roles match ollama-pull's OLLAMA_ROLE vocabulary so a migration and a service
# resolve the same way:
#
#   chat | chat-ctx  → EXIST_OLLAMA_URL_CHAT
#   extract          → EXIST_OLLAMA_URL_EXTRACT
#   embed            → EXIST_OLLAMA_URL_EMBED
#   vision           → EXIST_OLLAMA_URL_VISION
#
# Speech-to-text and text-to-speech are NOT here and get no keys of their own:
# wyoming-whisper and wyoming-piper run on CPU by design, so moving them frees no
# VRAM and there is nothing for this to spread. Home Assistant is told where they
# live in its own Wyoming integration, which no file in this repo controls.

# endpoint_for <role> → the URL serving that role, on stdout.
# An unknown role is a caller bug, not a config problem: fail loudly rather than
# silently handing back the default and sending traffic to the wrong box.
endpoint_for() {
    local role="${1:-}" specific=""
    local fallback="${EXIST_OLLAMA_URL:-http://ollama:11434}"

    case "$role" in
        chat|chat-ctx) specific="${EXIST_OLLAMA_URL_CHAT:-}" ;;
        extract)       specific="${EXIST_OLLAMA_URL_EXTRACT:-}" ;;
        embed)         specific="${EXIST_OLLAMA_URL_EMBED:-}" ;;
        vision)        specific="${EXIST_OLLAMA_URL_VISION:-}" ;;
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
