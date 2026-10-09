#!/usr/bin/env bash
# gmail_sync
#
# Fetches new Gmail messages via the Gmail REST API and emits each one to
# GMAIL_ROUTINE (gmail, or actual_budget_parse): the email body as the message
# body, its headers as params. Triggered by automation/cron/gmail-sync.md.
#
# GMAIL_FORWARD carries extra params to every emitted message, one key=value
# per line — how a bank-label cron hands actual_budget_parse its parse_script
# and account_id.
#
# Set GMAIL_LABEL_FILTER to any Gmail label (e.g. "MyLabel", "UNREAD") to
# filter which messages are synced. Each cron file can target a different label.
#
# Sync position is tracked in ${GMAIL_DIR}/history_id — a monotonically
# increasing cursor that survives restarts and extended downtime. If the
# cursor expires (Google purges history after ~30 days without a sync),
# the script automatically falls back to a full initial sync.
#
# Requires: curl, jq (both installed in the decree container)
# Credentials: ${GMAIL_DIR}/credentials.env (created by gmail/setup.sh)

set -euo pipefail

# ── Configuration ─────────────────────────────────────────────────────────────

GMAIL_DIR="${GMAIL_DIR:-/secrets/gmail}"
CREDENTIALS="${GMAIL_DIR}/credentials.env"
EMAILS_DIR="${EMAILS_DIR:-/work/.decree/emails}"
LABEL_FILTER="$DECREE_DATA_GMAIL_LABEL_FILTER"
INITIAL_SYNC_DAYS="$DECREE_DATA_GMAIL_INITIAL_SYNC_DAYS"
GMAIL_ROUTINE="$DECREE_DATA_GMAIL_ROUTINE"
GMAIL_FORWARD="$DECREE_DATA_GMAIL_FORWARD"

# Each trigger gets its own cursor file, keyed by label, to avoid stomping between crons
_history_key="${DECREE_DATA_GMAIL_HISTORY_KEY:-${LABEL_FILTER}}"
_history_slug=$(printf '%s' "$_history_key" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '_' | sed 's/_*$//')
HISTORY_FILE="${GMAIL_DIR}/history_id.${_history_slug}"

[ -f "$CREDENTIALS" ] || { echo "credentials not found at ${CREDENTIALS} — run: ./existential.sh run automation gmail-sync" >&2; exit 1; }

# ── Credentials ───────────────────────────────────────────────────────────────

# shellcheck disable=SC1090
source "$CREDENTIALS"

: "${GMAIL_CLIENT_ID:?GMAIL_CLIENT_ID not set in credentials.env}"
: "${GMAIL_CLIENT_SECRET:?GMAIL_CLIENT_SECRET not set in credentials.env}"
: "${GMAIL_REFRESH_TOKEN:?GMAIL_REFRESH_TOKEN not set in credentials.env}"

mkdir -p "$GMAIL_DIR"

# ── Token refresh ─────────────────────────────────────────────────────────────

refresh_token() {
    local response
    response=$(curl -sf --request POST \
        --data-urlencode "client_id=${GMAIL_CLIENT_ID}" \
        --data-urlencode "client_secret=${GMAIL_CLIENT_SECRET}" \
        --data-urlencode "refresh_token=${GMAIL_REFRESH_TOKEN}" \
        --data-urlencode "grant_type=refresh_token" \
        "https://oauth2.googleapis.com/token")

    local token
    token=$(printf '%s' "$response" | jq -r '.access_token // empty')

    if [ -z "$token" ]; then
        local err
        err=$(printf '%s' "$response" | jq -r '.error_description // .error // "unknown"')
        echo "Token refresh failed: ${err}" >&2
        return 1
    fi

    printf '%s' "$token"
}

# ── Label ID resolution ───────────────────────────────────────────────────────
# System labels (all-caps) are valid as-is. Custom labels are resolved from
# the label cache at ${GMAIL_DIR}/labels.json, populated by gmail-labels setup.

resolve_label_id() {
    local label_name="$1"
    case "$label_name" in
        INBOX|SENT|DRAFTS|SPAM|TRASH|UNREAD|STARRED|IMPORTANT)
            printf '%s' "$label_name"; return ;;
    esac
    local labels_file="${GMAIL_DIR}/labels.json"
    if [ ! -f "$labels_file" ]; then
        echo "Label cache missing. Run: ./existential.sh run automation gmail-labels" >&2
        exit 1
    fi
    local id
    id=$(jq -r --arg n "$label_name" \
        '.labels[] | select(.name == $n) | .id // empty' "$labels_file" | head -1)
    if [ -z "$id" ]; then
        echo "Label '${label_name}' not found in cache. Run: ./existential.sh run automation gmail-labels" >&2
        exit 1
    fi
    printf '%s' "$id"
}

# ── Base64url decode ──────────────────────────────────────────────────────────

b64url_decode() {
    local input="$1"
    [ -z "$input" ] || [ "$input" = "null" ] && return
    # Re-pad, translate to standard base64, decode
    local padded="$input"
    case $(( ${#input} % 4 )) in
        2) padded="${input}==" ;;
        3) padded="${input}=" ;;
    esac
    printf '%s' "$padded" | tr -- '-_' '+/' | base64 --decode 2>/dev/null || true
}

# ── Body extraction ───────────────────────────────────────────────────────────
# Searches for text/plain in this order:
#   1. Top-level payload (simple messages)
#   2. First-level parts (multipart/alternative)
#   3. Second-level parts (multipart/mixed containing multipart/alternative)
#   4. text/html fallback at first level
#   5. Top-level body as last resort

extract_body() {
    local msg_json="$1"
    local body_data

    body_data=$(printf '%s' "$msg_json" | jq -r '
        .payload |
        if .mimeType == "text/plain" then
            .body.data // ""
        elif ((.parts // []) | map(select(.mimeType == "text/plain")) | length) > 0 then
            [(.parts // [])[] | select(.mimeType == "text/plain")] | first | .body.data // ""
        elif ((.parts // []) | map(.parts // [] | map(select(.mimeType == "text/plain"))) | flatten | length) > 0 then
            [(.parts // [])[] | (.parts // [])[] | select(.mimeType == "text/plain")] | first | .body.data // ""
        elif ((.parts // []) | map(select(.mimeType == "text/html")) | length) > 0 then
            [(.parts // [])[] | select(.mimeType == "text/html")] | first | .body.data // ""
        else
            .body.data // ""
        end
    ')

    if [ -n "$body_data" ] && [ "$body_data" != "null" ]; then
        b64url_decode "$body_data"
    else
        printf '(no body)'
    fi
}

# ── Emit one message ──────────────────────────────────────────────────────────

write_message() {
    local access_token="$1"
    local msg_id="$2"
    # Idempotency: the history cursor is the real guard; this catches a resync
    # of a message the gmail machine has already filed.
    [ -f "${EMAILS_DIR}/gmail-${msg_id}.md" ] && return 0

    local response
    response=$(curl -sf \
        -H "Authorization: Bearer ${access_token}" \
        "https://gmail.googleapis.com/gmail/v1/users/me/messages/${msg_id}?format=full") \
        || { echo "Skipping message ${msg_id}: fetch failed (message may have been moved or deleted)" >&2; return 0; }

    # Extract headers (case-insensitive match via ascii_downcase)
    local subject from to date_hdr labels thread_id has_attachments

    subject=$(printf '%s' "$response" | jq -r '
        [.payload.headers[] | select(.name | ascii_downcase == "subject") | .value] | first // "(no subject)"
    ')
    from=$(printf '%s' "$response" | jq -r '
        [.payload.headers[] | select(.name | ascii_downcase == "from") | .value] | first // ""
    ')
    to=$(printf '%s' "$response" | jq -r '
        [.payload.headers[] | select(.name | ascii_downcase == "to") | .value] | first // ""
    ')
    date_hdr=$(printf '%s' "$response" | jq -r '
        [.payload.headers[] | select(.name | ascii_downcase == "date") | .value] | first // ""
    ')
    labels=$(printf '%s' "$response" | jq -r '
        [.labelIds // [] | .[]] | join(",")
    ')
    thread_id=$(printf '%s' "$response" | jq -r '.threadId // ""')
    has_attachments=$(printf '%s' "$response" | jq -r '
        ([.payload.parts // [] | .[] |
            select((.filename? // "") != "" and (.body.attachmentId? // "") != "")
        ] | length) > 0
    ')

    local body
    body=$(extract_body "$response")

    local -a fwd=()
    while IFS= read -r kv; do
        [ -n "$kv" ] && fwd+=(--param "$kv")
    done <<<"$GMAIL_FORWARD"

    # Values reach decree as argv and decree writes the YAML, so a subject with
    # quotes or a colon needs no escaping here.
    decree emit --machine "$GMAIL_ROUTINE" \
        --param gmail_id="$msg_id" --param thread_id="$thread_id" \
        --param from="$from" --param to="$to" --param subject="$subject" \
        --param date="$date_hdr" --param labels="$labels" \
        --param has_attachments="$has_attachments" \
        "${fwd[@]}" >/dev/null <<<"$body"
    echo "Enqueued: ${msg_id} — ${subject}"
}

# ── Initial sync ──────────────────────────────────────────────────────────────
# Fetches up to INITIAL_SYNC_DAYS of existing messages, then anchors
# the historyId cursor so subsequent runs are incremental.

initial_sync() {
    local access_token="$1"
    local query="label:${LABEL_FILTER}"

    if [ "${INITIAL_SYNC_DAYS:-0}" -gt 0 ]; then
        local since
        since=$(date -u -d "${INITIAL_SYNC_DAYS} days ago" +%s)
        query="${query} after:${since}"
    fi

    echo "Initial sync: query='${query}'"

    local count=0 page_token="" response curl_args

    while true; do
        curl_args=(-sG
            --data-urlencode "q=${query}"
            --data-urlencode "maxResults=100"
            -H "Authorization: Bearer ${access_token}"
        )
        [ -n "$page_token" ] && curl_args+=(--data-urlencode "pageToken=${page_token}")
        curl_args+=("https://gmail.googleapis.com/gmail/v1/users/me/messages")

        response=$(curl -sf "${curl_args[@]}")

        while IFS= read -r id; do
            [ -z "$id" ] && continue
            write_message "$access_token" "$id"
            count=$(( count + 1 ))
        done < <(printf '%s' "$response" | jq -r '[.messages // [] | .[].id | select(. and . != "null")] | unique | .[]')

        page_token=$(printf '%s' "$response" | jq -r '.nextPageToken // empty')
        [ -z "$page_token" ] && break
    done

    echo "Initial sync complete: ${count} message(s)"

    # Anchor the cursor after fetching — get the latest historyId from profile
    local profile
    profile=$(curl -sf \
        -H "Authorization: Bearer ${access_token}" \
        "https://gmail.googleapis.com/gmail/v1/users/me/profile")

    local new_history_id
    new_history_id=$(printf '%s' "$profile" | jq -r '.historyId')

    printf '%s' "$new_history_id" > "${HISTORY_FILE}.tmp"
    mv "${HISTORY_FILE}.tmp" "$HISTORY_FILE"
    echo "Cursor anchored: historyId=${new_history_id}"
}

# ── Incremental sync ──────────────────────────────────────────────────────────
# Fetches only messages added since the last saved historyId.
# Handles cursor expiry (404) by falling back to initial_sync automatically.

incremental_sync() {
    local access_token="$1"
    local history_id="$2"

    echo "Incremental sync from historyId: ${history_id}"

    local count=0 page_token="" new_history_id="$history_id" response error_code curl_args

    while true; do
        curl_args=(-sG
            --data-urlencode "startHistoryId=${history_id}"
            --data-urlencode "historyTypes=messageAdded"
            --data-urlencode "labelId=${LABEL_ID}"
            --data-urlencode "maxResults=500"
            -H "Authorization: Bearer ${access_token}"
        )
        [ -n "$page_token" ] && curl_args+=(--data-urlencode "pageToken=${page_token}")
        curl_args+=("https://gmail.googleapis.com/gmail/v1/users/me/history")

        response=$(curl "${curl_args[@]}")
        error_code=$(printf '%s' "$response" | jq -r '.error.code // empty')

        if [ "$error_code" = "404" ]; then
            # historyId is older than ~30 days — Google has purged the history
            echo "historyId expired. Clearing cursor and falling back to initial sync."
            rm -f "$HISTORY_FILE"
            initial_sync "$access_token"
            return
        fi

        if [ -n "$error_code" ]; then
            local err_msg
            err_msg=$(printf '%s' "$response" | jq -r '.error.message // "unknown"')
            echo "Gmail API error ${error_code}: ${err_msg}" >&2
            exit 1
        fi

        # Advance cursor even if no records were returned
        local latest
        latest=$(printf '%s' "$response" | jq -r '.historyId // empty')
        [ -n "$latest" ] && new_history_id="$latest"

        while IFS= read -r id; do
            [ -z "$id" ] && continue
            write_message "$access_token" "$id"
            count=$(( count + 1 ))
        done < <(printf '%s' "$response" | jq -r '
            [.history // [] | .[].messagesAdded // [] | .[].message.id | select(. and . != "null")] | unique | .[]
        ')

        page_token=$(printf '%s' "$response" | jq -r '.nextPageToken // empty')
        [ -z "$page_token" ] && break
    done

    # Save the advanced cursor atomically
    printf '%s' "$new_history_id" > "${HISTORY_FILE}.tmp"
    mv "${HISTORY_FILE}.tmp" "$HISTORY_FILE"
    echo "Incremental sync complete: ${count} new message(s), historyId=${new_history_id}"
}

# ── Auth failure tracking ─────────────────────────────────────────────────────

_AUTH_FAILURE_FILE="${GMAIL_DIR}/auth_failure"

_handle_auth_failure() {
    if [ ! -f "$_AUTH_FAILURE_FILE" ]; then
        touch "$_AUTH_FAILURE_FILE"
        decree emit --machine notify --param ntfy_title="Gmail sync: authorization failed" \
            --param ntfy_priority=high --param ntfy_tags=warning,key >/dev/null <<'NOTIFY'
Gmail token refresh failed. The gmail_sync machine is paused.

To reauthorize: ./existential.sh run automation gmail-sync
NOTIFY
        echo "Auth failure notification queued." >&2
    fi
}

# ── Main ──────────────────────────────────────────────────────────────────────

echo "Refreshing access token..."
if ! ACCESS_TOKEN=$(refresh_token); then
    _handle_auth_failure
    exit 1
fi

# Clear failure state on successful refresh (enables re-notification on future failures)
rm -f "$_AUTH_FAILURE_FILE"
echo "Token refreshed."

LABEL_ID=$(resolve_label_id "$LABEL_FILTER")
[ "$LABEL_ID" != "$LABEL_FILTER" ] && echo "Resolved label '${LABEL_FILTER}' → ${LABEL_ID}"

HISTORY_ID=""
[ -f "$HISTORY_FILE" ] && HISTORY_ID=$(cat "$HISTORY_FILE")

if [ -z "$HISTORY_ID" ]; then
    initial_sync "$ACCESS_TOKEN"
else
    incremental_sync "$ACCESS_TOKEN" "$HISTORY_ID"
fi
