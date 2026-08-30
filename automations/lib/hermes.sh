#!/usr/bin/env bash
# hermes.sh — shared helpers for talking to the hermes gateway.
#
# Sourced, never run. Hermes is an OpenAI-compatible endpoint, so this is a thin
# curl wrapper — the value is that callers do not each carry their own copy of
# the request shape.
#
#   source "$(dirname "${BASH_SOURCE[0]}")/../lib/hermes.sh"
#
#   hermes_chat <system> <user> <max_tokens>   → assistant text on stdout
#   hermes_gate <criteria> <text>              → 0 = YES, 1 = NO, 2 = no verdict
#   hermes_profile_url <profile>               → base URL for a named profile
#
# hermes_gate's exit codes matter to the caller: 1 is a real verdict (the content
# does not match, move on) while 2 means the model never answered — a gateway
# that is down or slow. Callers should fail the message on 2 so decree retries,
# rather than silently treating "no answer" as "no match".
#
# Env vars:
#   HERMES_GATEWAY_URL  default http://hermes-agent:8642 (used by hermes_profile_url)
#   HERMES_API_URL   default http://hermes-agent:8642/v1
#   HERMES_API_KEY   bearer token; omitted from the request when empty
#   HERMES_MODEL     optional; the gateway's own default is used when unset
#   HERMES_TIMEOUT   seconds, default 120

# Base URL for one hermes profile, for callers that set HERMES_API_URL per call.
#
# Profile multiplexing (GATEWAY_MULTIPLEX_PROFILES) serves every named profile
# off the one listener under /p/<profile>/v1; the default profile keeps the bare
# /v1. An unknown profile 404s rather than falling back, so a typo here fails
# loudly instead of quietly running against the wrong toolset.
hermes_profile_url() {
    local profile="${1:-}"
    local base="${HERMES_GATEWAY_URL:-http://hermes-agent:8642}"
    base="${base%/}"
    case "$profile" in
        ""|default) printf '%s/v1\n' "$base" ;;
        *)          printf '%s/p/%s/v1\n' "$base" "$profile" ;;
    esac
}

hermes_chat() {
    local system="$1" user="$2" max_tokens="${3:-1000}" payload
    local url="${HERMES_API_URL:-http://hermes-agent:8642/v1}"
    local -a args=(-fsS --max-time "${HERMES_TIMEOUT:-120}" -X POST
        "${url%/}/chat/completions"
        -H "Content-Type: application/json")

    if [ -n "${HERMES_API_KEY:-}" ]; then
        args+=(-H "Authorization: Bearer ${HERMES_API_KEY}")
    fi

    payload="$(jq -n \
        --arg s "$system" --arg u "$user" \
        --argjson mt "$max_tokens" \
        --arg model "${HERMES_MODEL:-}" \
        '{messages:[{role:"system",content:$s},{role:"user",content:$u}],
          max_tokens:$mt, temperature:0}
         + (if $model == "" then {} else {model:$model} end)')"

    curl "${args[@]}" -d "$payload" | jq -r '.choices[0].message.content // empty'
}

# Ask whether some text matches a natural-language criterion.
#
# The prompt is deliberately stingy — a gate that says YES to everything costs a
# model call per file and then a full agent run, so the default posture is NO.
hermes_gate() {
    local criteria="$1" text="$2" verdict

    local system="You judge whether a document matches a criterion. You are shown one document.
Decide whether it matches: ${criteria}

Be strict. Most documents do not match. A passing mention, a link with no thought
attached, a stub, or a file that merely touches the subject is NOT a match. Only
answer YES when the document genuinely matches and acting on it would be useful.

Reply with exactly one line, in this format:
YES: <one sentence saying why>
or
NO"

    verdict="$(hermes_chat "$system" "$text" 200 || true)"
    verdict="$(printf '%s' "$verdict" | head -1 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

    if [ -z "$verdict" ]; then
        return 2
    fi

    case "$verdict" in
        YES*|yes*)
            # Reason on stdout so the caller can log or forward it.
            printf '%s\n' "$(printf '%s' "$verdict" | sed 's/^[Yy][Ee][Ss][[:space:]]*:\?[[:space:]]*//')"
            return 0
            ;;
        NO*|no*) return 1 ;;
        *)       return 2 ;;
    esac
}
