#!/usr/bin/env bash
# Telegram Ingest
#
# Polls the Telegram Bot API for new photo and image-document messages, downloads
# each file, and saves it to TELEGRAM_RCLONE_DEST. An upload through Nextcloud
# fires its file event → file_router → file_processor → ollama-ocr, so the
# image is read automatically.
#
# Tracks the last-seen update_id in a cursor file to avoid reprocessing.
# Designed to run on a cron (automation-examples/cron/telegram-poll.md).
#
# Credentials: /secrets/telegram/credentials.env
#   TELEGRAM_BOT_TOKEN=<your-bot-token>

set -euo pipefail

# ── Configuration ─────────────────────────────────────────────────────────────

TELEGRAM_SECRETS_DIR="${TELEGRAM_SECRETS_DIR:-/secrets/telegram}"
TELEGRAM_RCLONE_DEST="$DECREE_DATA_TELEGRAM_RCLONE_DEST"
_credentials="${TELEGRAM_SECRETS_DIR}/credentials.env"
_offset_file="${TELEGRAM_SECRETS_DIR}/offset.txt"

# shellcheck source=/dev/null  # runtime path, contents are credentials
[ -f "$_credentials" ] && source "$_credentials"

[ -n "${TELEGRAM_BOT_TOKEN:-}" ] || { echo "TELEGRAM_BOT_TOKEN not set — create ${_credentials}"; exit 1; }

_api="https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}"

# ── Read cursor ────────────────────────────────────────────────────────────────

_offset=0
[ -f "$_offset_file" ] && _offset=$(cat "$_offset_file")
echo "Polling (offset: $_offset)..."

# ── Fetch updates ──────────────────────────────────────────────────────────────

_response=$(curl -sf "${_api}/getUpdates?offset=${_offset}&limit=100&timeout=0")
_count=$(echo "$_response" | jq '.result | length')

if [ "$_count" -eq 0 ]; then
    echo "No new updates."
    exit 0
fi

echo "Updates: $_count"

# ── Process each update ────────────────────────────────────────────────────────

_saved=0

for i in $(seq 0 $((_count - 1))); do
    _update=$(echo "$_response" | jq ".result[$i]")

    # Photo message: pick largest resolution (last in array)
    if echo "$_update" | jq -e '.message.photo' >/dev/null 2>&1; then
        _file_id=$(echo "$_update" | jq -r '.message.photo | last | .file_id')
        _date=$(echo "$_update" | jq -r '.message.date')
        _filename="${_date}_${_file_id}.jpg"

    # Image document (e.g. file sent as document with image MIME type)
    elif echo "$_update" | jq -e 'select(.message.document.mime_type | strings | startswith("image/"))' >/dev/null 2>&1; then
        _file_id=$(echo "$_update" | jq -r '.message.document.file_id')
        _filename=$(echo "$_update" | jq -r '.message.document.file_name // "image.jpg"')

    else
        continue
    fi

    # Resolve file path on Telegram's servers
    _file_info=$(curl -sf "${_api}/getFile?file_id=${_file_id}")
    _file_path=$(echo "$_file_info" | jq -r '.result.file_path // empty')

    if [ -z "$_file_path" ]; then
        echo "Could not resolve file path for file_id: $_file_id — skipping."
        continue
    fi

    # Download from Telegram and upload to rclone destination
    _dest="${TELEGRAM_RCLONE_DEST}/${_filename}"
    echo "Saving: $_filename → $_dest"

    curl -sf "https://api.telegram.org/file/bot${TELEGRAM_BOT_TOKEN}/${_file_path}" \
        | rclone rcat "$_dest" --config /secrets/rclone/rclone.conf

    _saved=$((_saved + 1))
done

# ── Advance cursor ─────────────────────────────────────────────────────────────

_new_offset=$(echo "$_response" | jq '[.result[].update_id] | max + 1')
mkdir -p "$TELEGRAM_SECRETS_DIR"
echo "$_new_offset" > "$_offset_file"

echo "Done. Saved ${_saved} image(s). Next offset: ${_new_offset}"
