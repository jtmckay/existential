#!/usr/bin/env bash
# homeassistant-wyoming-hermes — wire up HA's voice pipeline headlessly:
# Wyoming STT/TTS plus Hermes as the conversation agent.
#
# Runs as a decree migration (once). Every step here is exactly what a human
# clicking through Settings -> Devices & Services would do, replayed over
# HA's own APIs — verified end-to-end against a disposable copy of this
# stack's real HA image, the real wyoming-whisper/wyoming-piper containers,
# and the real hermes-agent, including an actual conversation.process round
# trip that got a real reply back through Hermes.
#
# extended_openai_conversation (installed by services/homeassistant/
# exist.initial.sh, pinned) is what makes "conversation agent = Hermes"
# possible — HA's own built-in OpenAI Conversation integration has no
# custom-endpoint option (verified against its 2026.8.2 source). If
# exist.initial.sh hasn't run yet, or HA hasn't been restarted since it did,
# this exits with that as the explicit reason rather than guessing.
#
# Auth: a fresh username/password login (homeassistant-onboarding.sh's
# auth_code is one-time-use and long since consumed by the time this runs,
# so this does its own independent login).
#
# REST covers everything except the Assist pipeline itself, which is
# websocket-only (no REST equivalent) — that one step shells out to
# automation/lib/homeassistant-ws.ts via tsx.
#
# Idempotent: checks for an existing entry/pipeline by name before creating
# anything, so a re-run (or decree retrying a prior failure) is a no-op.
#
# Env vars (passed through the decree container's compose env):
#   HOMEASSISTANT_URL                           default http://homeassistant:8123
#   HOMEASSISTANT_ADMIN_USER / HOMEASSISTANT_ADMIN_PASSWORD
#   HERMES_API_KEY
set -euo pipefail

HOMEASSISTANT_URL="${HOMEASSISTANT_URL:-http://homeassistant:8123}"
CLIENT_ID="${HOMEASSISTANT_URL%/}/"
WS_URL="${HOMEASSISTANT_URL/http/ws}/api/websocket"
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)"

if [[ "${DECREE_PRE_CHECK:-}" == "true" ]]; then
    command -v curl >/dev/null 2>&1             || { echo "curl not found" >&2; exit 1; }
    command -v jq >/dev/null 2>&1                || { echo "jq not found" >&2; exit 1; }
    command -v tsx >/dev/null 2>&1               || { echo "tsx not found" >&2; exit 1; }
    [[ -n "${HOMEASSISTANT_ADMIN_USER:-}" ]]     || { echo "HOMEASSISTANT_ADMIN_USER not set" >&2; exit 1; }
    [[ -n "${HOMEASSISTANT_ADMIN_PASSWORD:-}" ]] || { echo "HOMEASSISTANT_ADMIN_PASSWORD not set" >&2; exit 1; }
    [[ -n "${HERMES_API_KEY:-}" ]]               || { echo "HERMES_API_KEY not set" >&2; exit 1; }
    exit 0
fi

# _api METHOD PATH [JSON_BODY] — authenticated REST call. Checks the HTTP
# status itself: HA answers a bad flow step with a 2xx-shaped JSON error in
# some cases and a plain-text 4xx/5xx in others (RequirementsNotFound is the
# latter), so curl's own exit status alone would miss half of that.
_api() {
    local method="$1" path="$2" data="${3:-}" code body args=()
    body=$(mktemp)
    args=(-sS --max-time 10 -o "$body" -w '%{http_code}' -X "$method" \
        -H "Authorization: Bearer ${ACCESS_TOKEN}" "${HOMEASSISTANT_URL}${path}")
    [[ -n "$data" ]] && args+=(-H "Content-Type: application/json" -d "$data")
    code=$(curl "${args[@]}")
    if [[ "$code" != 2* ]]; then
        echo "${method} ${path} -> ${code}: $(cat "$body")" >&2
        rm -f "$body"
        return 1
    fi
    cat "$body"
    rm -f "$body"
}

# One websocket round trip: auth, send the command, print its `result`.
_ws() {
    HA_WS_URL="$WS_URL" HA_WS_TOKEN="$ACCESS_TOKEN" HA_WS_COMMAND="$1" \
        tsx "${LIB_DIR}/homeassistant-ws.ts"
}

# Three-call login dance (start a flow, submit credentials, exchange the
# resulting code for a token) — same shape as homeassistant-onboarding.sh's,
# done independently since that migration's auth_code cannot be reused.
_login() {
    local flow code
    flow=$(curl -sS --max-time 10 -X POST "${HOMEASSISTANT_URL}/auth/login_flow" \
        -H "Content-Type: application/json" \
        -d "$(jq -n --arg cid "$CLIENT_ID" '{client_id:$cid, handler:["homeassistant",null], redirect_uri:($cid+"?auth_callback=1")}')")
    code=$(curl -sS --max-time 10 -X POST "${HOMEASSISTANT_URL}/auth/login_flow/$(echo "$flow" | jq -r .flow_id)" \
        -H "Content-Type: application/json" \
        -d "$(jq -n --arg u "$HOMEASSISTANT_ADMIN_USER" --arg p "$HOMEASSISTANT_ADMIN_PASSWORD" --arg cid "$CLIENT_ID" \
            '{username:$u, password:$p, client_id:$cid}')" | jq -r .result)
    curl -sS --max-time 10 -X POST "${HOMEASSISTANT_URL}/auth/token" \
        --data-urlencode "client_id=${CLIENT_ID}" \
        --data-urlencode "grant_type=authorization_code" \
        --data-urlencode "code=${code}" | jq -r .access_token
}

ACCESS_TOKEN=$(_login)
[[ -n "$ACCESS_TOKEN" && "$ACCESS_TOKEN" != "null" ]] || { echo "Could not log in as ${HOMEASSISTANT_ADMIN_USER}" >&2; exit 1; }

handlers=$(_api GET /api/config/config_entries/flow_handlers)
if ! echo "$handlers" | jq -e 'index("extended_openai_conversation")' >/dev/null; then
    echo "extended_openai_conversation isn't loaded yet — restart the homeassistant" >&2
    echo "container (docker compose up -d homeassistant) so it picks up the files" >&2
    echo "exist.initial.sh installed, then re-run this migration." >&2
    exit 1
fi

# HA's config-entry listing never includes an entry's `data` (host/port,
# api_key — verified against source: ConfigEntry.as_json_fragment omits it
# entirely), so idempotency here goes by `title` instead — verified stable
# across repeated live creations: wyoming names the entry after the service
# it discovers ("faster-whisper", "piper"), not the container hostname.
_entries() { _api GET "/api/config/config_entries/entry?domain=$1"; }

_create_wyoming() {
    local host="$1" port="$2" match="$3"
    _entries wyoming | jq -e --arg m "$match" 'any(.[]; .title | test($m; "i"))' >/dev/null && return 0
    local flow_id
    flow_id=$(_api POST /api/config/config_entries/flow '{"handler":"wyoming"}' | jq -r .flow_id)
    _api POST "/api/config/config_entries/flow/${flow_id}" "$(jq -n --arg h "$host" --argjson p "$port" '{host:$h, port:$p}')" >/dev/null
    echo "Created Wyoming entry for ${host}:${port}."
}

_create_hermes_conversation() {
    [[ "$(_entries extended_openai_conversation | jq 'length')" -gt 0 ]] && return 0
    local flow_id
    flow_id=$(_api POST /api/config/config_entries/flow '{"handler":"extended_openai_conversation"}' | jq -r .flow_id)
    _api POST "/api/config/config_entries/flow/${flow_id}" "$(jq -n --arg key "$HERMES_API_KEY" \
        '{name:"Hermes", api_key:$key, base_url:"http://hermes-agent:8642/v1", api_provider:"openai"}')" >/dev/null
    echo "Created the Hermes conversation-agent entry."
}

_create_wyoming wyoming-whisper 10300 whisper
_create_wyoming wyoming-piper 10200 piper
_create_hermes_conversation

STT_ENTRY_ID=$(_entries wyoming | jq -r '.[] | select(.title | test("whisper";"i")) | .entry_id' | head -1)
TTS_ENTRY_ID=$(_entries wyoming | jq -r '.[] | select(.title | test("piper";"i")) | .entry_id' | head -1)
CONV_ENTRY_ID=$(_entries extended_openai_conversation | jq -r '.[0].entry_id')

# entity_id for the entity registered against a config entry, filtered to one
# domain — robust against whatever title wyoming picked, unlike guessing a
# slug from the hostname.
_entity_for_entry() {
    local entry_id="$1" domain="$2"
    _ws '{"type":"config/entity_registry/list"}' \
        | jq -r --arg cid "$entry_id" --arg dom "$domain" \
            '.[] | select(.config_entry_id==$cid and (.entity_id | startswith($dom+"."))) | .entity_id' \
        | head -1
}

STT_ENTITY=$(_entity_for_entry "$STT_ENTRY_ID" stt)
TTS_ENTITY=$(_entity_for_entry "$TTS_ENTRY_ID" tts)
CONV_ENTITY=$(_entity_for_entry "$CONV_ENTRY_ID" conversation)

if [[ -z "$STT_ENTITY" || -z "$TTS_ENTITY" || -z "$CONV_ENTITY" ]]; then
    echo "Could not resolve entity ids (stt=${STT_ENTITY:-?} tts=${TTS_ENTITY:-?} conversation=${CONV_ENTITY:-?})" >&2
    exit 1
fi

# Idempotent by name: the pipeline store has no unique constraint on name, so
# check first rather than accumulate a duplicate on every re-run.
EXISTING_PIPELINE=$(_ws '{"type":"assist_pipeline/pipeline/list"}' | jq -r '.pipelines[]? | select(.name=="Hermes") | .id' | head -1)
if [[ -n "$EXISTING_PIPELINE" ]]; then
    echo "Pipeline 'Hermes' already exists — nothing to do."
    exit 0
fi

PIPELINE=$(_ws "$(jq -n --arg conv "$CONV_ENTITY" --arg stt "$STT_ENTITY" --arg tts "$TTS_ENTITY" '{
    type: "assist_pipeline/pipeline/create",
    name: "Hermes",
    conversation_engine: $conv,
    conversation_language: "en",
    language: "en",
    stt_engine: $stt,
    stt_language: "en",
    tts_engine: $tts,
    tts_language: "en",
    tts_voice: null,
    wake_word_entity: null,
    wake_word_id: null
}')")
PIPELINE_ID=$(echo "$PIPELINE" | jq -r .id)

_ws "$(jq -n --arg id "$PIPELINE_ID" '{type:"assist_pipeline/pipeline/set_preferred", pipeline_id:$id}')" >/dev/null

echo "Created and activated the 'Hermes' Assist pipeline (stt=${STT_ENTITY}, tts=${TTS_ENTITY}, conversation=${CONV_ENTITY})."
