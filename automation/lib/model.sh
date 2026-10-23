#!/usr/bin/env bash
# model.sh — how a decree script reaches a model.
#
# Sourced, never run. Every model role's address is an OpenAI-compatible base
# URL ending /v1, so ollama, a llama.cpp server or anything else that serves
# /v1/chat/completions answers the same request. hermes is not involved: a
# script that wants an agent with tools uses hermes.sh, which is built on this.
#
#   source "${DECREE_LIB}/model.sh"
#
#   model_url <role>                         → base URL serving that role
#   model_chat <system> <user> [max_tokens]  → assistant text on stdout
#   model_gate <criteria> <text>             → 0 = YES, 1 = NO, 2 = no verdict
#
# model_gate's exit codes matter to the caller: 1 is a real verdict (the content
# does not match, move on) while 2 means the model never answered — a server
# that is down or slow. Callers should fail the message on 2 so decree retries,
# rather than silently treating "no answer" as "no match".
#
# Env vars:
#   EXIST_MODEL_URL, EXIST_MODEL_URL_<ROLE>  the endpoints (compose passes them)
#   EXIST_MODEL_<ROLE>   the tag a role sends as "model"
#   MODEL_ROLE       role model_chat talks to, default chat
#   MODEL_URL        overrides the role's URL (hermes_chat aims it at the gateway)
#   MODEL_NAME       overrides the role's tag; set but EMPTY sends no "model" at
#                    all, so the server's own default answers
#   MODEL_API_KEY    bearer token; omitted from the request when empty
#   MODEL_TIMEOUT    seconds, default 120
#   MODEL_TEMPERATURE  default 0

# model_url <role> — the in-container copy of src/utils/model-endpoints.sh's
# endpoint_for, which this container cannot see. test-model-endpoints.sh asserts
# the two resolve every role identically, so never add a fallback in one only.
model_url() {
    local role="${1:-}" specific=""
    case "$role" in
        chat|chat-ctx) specific="${EXIST_MODEL_URL_CHAT:-}" ;;
        extract)       specific="${EXIST_MODEL_URL_EXTRACT:-}" ;;
        embed)         specific="${EXIST_MODEL_URL_EMBED:-}" ;;
        vision)        specific="${EXIST_MODEL_URL_VISION:-}" ;;
        *)
            echo "model_url: unknown role '${role}' (chat|chat-ctx|extract|embed|vision)" >&2
            return 1
            ;;
    esac
    printf '%s\n' "${specific:-${EXIST_MODEL_URL:-http://ollama:11434/v1}}"
}

# model_tag <role> — the EXIST_MODEL_* tag for a role (empty when unset).
model_tag() {
    case "${1:-}" in
        chat|chat-ctx) printf '%s\n' "${EXIST_MODEL_CHAT:-}" ;;
        extract)       printf '%s\n' "${EXIST_MODEL_EXTRACT:-}" ;;
        embed)         printf '%s\n' "${EXIST_MODEL_EMBED:-}" ;;
        vision)        printf '%s\n' "${EXIST_MODEL_VISION:-}" ;;
        *)             return 1 ;;
    esac
}

model_chat() {
    local system="$1" user="$2" max_tokens="${3:-1000}" payload url model
    local role="${MODEL_ROLE:-chat}"
    url="${MODEL_URL:-$(model_url "$role")}" || return 1
    model="${MODEL_NAME-$(model_tag "$role")}"
    local -a args=(-fsS --max-time "${MODEL_TIMEOUT:-120}" -X POST
        "${url%/}/chat/completions"
        -H "Content-Type: application/json")

    if [ -n "${MODEL_API_KEY:-}" ]; then
        args+=(-H "Authorization: Bearer ${MODEL_API_KEY}")
    fi

    payload="$(jq -n \
        --arg s "$system" --arg u "$user" \
        --argjson mt "$max_tokens" \
        --argjson t "${MODEL_TEMPERATURE:-0}" \
        --arg model "$model" \
        '{messages:[{role:"system",content:$s},{role:"user",content:$u}],
          max_tokens:$mt, temperature:$t}
         + (if $model == "" then {} else {model:$model} end)')"

    curl "${args[@]}" -d "$payload" | jq -r '.choices[0].message.content // empty'
}

# Ask whether some text matches a natural-language criterion.
#
# The prompt is deliberately stingy — a gate that says YES to everything costs a
# model call per file and then a full run, so the default posture is NO.
model_gate() {
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

    verdict="$(model_chat "$system" "$text" 200 || true)"
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
