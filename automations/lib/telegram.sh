#!/usr/bin/env bash
# telegram.sh — source this at the top of any routine that calls the Telegram Bot API.
#
# Prerequisites (set before sourcing):
#   TELEGRAM_BOT_TOKEN  — bot token from @BotFather
#
# Functions exposed after sourcing:
#   telegram_send_message   chat_id text [reply_to_message_id]  → message_id
#   telegram_send_reply     reply_to_message_id text            → message_id  (uses TELEGRAM_CHAT_ID)
#   telegram_get_file_url   file_id                             → HTTPS download URL
#   telegram_download_file  file_id dest_path                   → (writes file to dest_path)
#
# Typical usage:
#
#   source "$(dirname "${BASH_SOURCE[0]}")/../../lib/telegram.sh"
#
#   _msg_id=$(telegram_send_message "$TELEGRAM_CHAT_ID" "Hello!")
#   telegram_send_reply "$_msg_id" "This is a reply."

_TELEGRAM_API_BASE="https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}"

telegram_send_message() {
    local chat_id="$1"
    local text="$2"
    local reply_to="${3:-}"

    local payload
    payload=$(jq -nc \
        --argjson chat_id "$chat_id" \
        --arg text "$text" \
        '{"chat_id": $chat_id, "text": $text, "parse_mode": "Markdown"}')

    if [ -n "$reply_to" ]; then
        payload=$(echo "$payload" | jq --argjson r "$reply_to" '.reply_to_message_id = $r')
    fi

    curl -sf -X POST "${_TELEGRAM_API_BASE}/sendMessage" \
        -H "Content-Type: application/json" \
        -d "$payload" \
        | jq -r '.result.message_id'
}

telegram_send_reply() {
    local reply_to_message_id="$1"
    local text="$2"
    telegram_send_message "$TELEGRAM_CHAT_ID" "$text" "$reply_to_message_id"
}

telegram_get_file_url() {
    local file_id="$1"
    local file_path
    file_path=$(curl -sf "${_TELEGRAM_API_BASE}/getFile?file_id=${file_id}" \
        | jq -r '.result.file_path')
    echo "https://api.telegram.org/file/bot${TELEGRAM_BOT_TOKEN}/${file_path}"
}

telegram_download_file() {
    local file_id="$1"
    local dest="$2"
    local url
    url=$(telegram_get_file_url "$file_id")
    curl -sf "$url" -o "$dest"
}
