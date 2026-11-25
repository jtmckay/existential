---
name: model
x-exist-project: automation
needs:
  - fleet
x-exist-lib:
  model.sh: |
    #!/usr/bin/env bash
    # model.sh — how a decree script reaches a model.
    #
    # Sourced, never run. A model's address is an OpenAI-compatible base URL ending
    # /v1, so ollama, a llama.cpp server, Strata or anything else that serves
    # /v1/chat/completions answers the same request. A script that wants an agent
    # with tools uses pi.sh (this model) or agent.sh (Claude).
    #
    #   source ".decree/lib/model.sh"
    #
    #   model_url                                → this host's own model URL
    #   model_chat <system> <user> [max_tokens]  → assistant text on stdout
    #   model_gate <criteria> <text>             → 0 = YES, 1 = NO, 2 = no verdict
    #
    # model_gate's exit codes matter to the caller: 1 is a real verdict (the content
    # does not match, move on) while 2 means the model never answered — a server
    # that is down or slow. Callers should fail the message on 2 so decree retries,
    # rather than silently treating "no answer" as "no match".
    #
    # Env vars:
    #   EXIST_MODEL_URL      this host's own model URL (compose passes it)
    #   EXIST_MODEL_<ROLE>   the model a role (chat, vision) sends as "model"
    #   MODEL_ROLE       role model_chat talks to, default chat
    #   MODEL_URL        overrides the role's URL
    #   MODEL_NAME       overrides the role's tag; set but EMPTY sends no "model" at
    #                    all, so the server's own default answers
    #   MODEL_API_KEY    bearer token, default EXIST_FLEET_SECRET; omitted when empty
    #   MODEL_TIMEOUT    seconds, default 120
    #   MODEL_TEMPERATURE  default 0
    #
    # With the fleet on (EXIST_FLEET_SECRET), a call with no MODEL_URL goes to the fleet
    # service (llm or strata) whose offer lists the role's model, under its lease
    # (fleet.sh): a run of calls shares one lease, given back 5 s after the last. No host
    # offers that model: EXIST_MODEL_URL.

    # model_url — this host's own model URL, where a call goes when the fleet has none.
    model_url() { printf '%s\n' "${EXIST_MODEL_URL:-http://ollama:11434/v1}"; }

    # model_tag <role> — the EXIST_MODEL_* tag for a role (empty when unset).
    model_tag() {
        case "${1:-}" in
            chat|chat-ctx) printf '%s\n' "${EXIST_MODEL_CHAT:-}" ;;
            vision)        printf '%s\n' "${EXIST_MODEL_VISION:-}" ;;
            *)             return 1 ;;
        esac
    }

    # shellcheck source=fleet.sh
    if [ -f "$(dirname "${BASH_SOURCE[0]}")/fleet.sh" ]; then
        source "$(dirname "${BASH_SOURCE[0]}")/fleet.sh"
    else
        fleet_on() { return 1; }; fleet_use() { return 3; }; fleet_done() { :; }
    fi

    # model_service <model> — the fleet service (llm or strata) whose offer lists this
    # model, or nothing.
    model_service() {
        [ -n "$1" ] || return 0
        fleet_offers 2>/dev/null | jq -r --arg m "$1" \
            'select((.service == "llm" or .service == "strata") and any(.models[]?; .id == $m)) | .service' |
            head -n 1
    }

    # model_base <role> — sets MODEL_BASE to where a call goes now: the fleet service that
    # serves the role's model, holding its lease (end the call with fleet_done
    # "$MODEL_SERVICE"), else MODEL_URL or EXIST_MODEL_URL. Not in $(...): the lease's
    # token lives in this shell.
    model_base() {
        local rc=0
        MODEL_BASE="" MODEL_SERVICE=""
        if [ -z "${MODEL_URL:-}" ] && fleet_on 2>/dev/null; then
            MODEL_SERVICE="$(model_service "${MODEL_NAME-$(model_tag "$1")}")"
            if [ -n "$MODEL_SERVICE" ]; then
                fleet_use "$MODEL_SERVICE" || rc=$?
                if [ "$rc" -eq 0 ]; then MODEL_BASE="$FLEET_URL"; return 0; fi
                [ "$rc" -eq 3 ] || { echo "model: no host that offers ${MODEL_SERVICE} would lease it" >&2; return 1; }
            fi
        fi
        MODEL_BASE="${MODEL_URL:-$(model_url)}"
    }

    model_chat() {
        local system="$1" user="$2" max_tokens="${3:-1000}" payload url model rc=0
        local role="${MODEL_ROLE:-chat}"
        model_base "$role" || return 1
        url="$MODEL_BASE"
        model="${MODEL_NAME-$(model_tag "$role")}"
        local -a args=(-fsS --max-time "${MODEL_TIMEOUT:-120}" -X POST
            "${url%/}/chat/completions"
            -H "Content-Type: application/json")

        local key="${MODEL_API_KEY:-${EXIST_FLEET_SECRET:-}}"
        if [ -n "$key" ]; then
            args+=(-H "Authorization: Bearer $key")
        fi

        payload="$(jq -n \
            --arg s "$system" --arg u "$user" \
            --argjson mt "$max_tokens" \
            --argjson t "${MODEL_TEMPERATURE:-0}" \
            --arg model "$model" \
            '{messages:[{role:"system",content:$s},{role:"user",content:$u}],
              max_tokens:$mt, temperature:$t}
             + (if $model == "" then {} else {model:$model} end)')"

        curl "${args[@]}" -d "$payload" | jq -r '.choices[0].message.content // empty' || rc=$?
        [ -z "$MODEL_SERVICE" ] || fleet_done "$MODEL_SERVICE"
        return "$rc"
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
---
# model

One answer from a model's OpenAI-compatible /v1 URL, for any script: model_chat, model_gate, model_url (.decree/lib/model.sh).
