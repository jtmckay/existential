#!/usr/bin/env bash
# Telegram Receipt
#
# Polls the Telegram Bot API for new messages and routes them:
#
#   Photo reply to a pending transaction notification
#     → OCR the receipt as JSON → validate total → split in Actual Budget
#     → reply with breakdown; user can reply "no" to revert
#
#   Text "no" (case-insensitive) reply to a split breakdown message
#     → revert the split back to a single transaction → confirm in Telegram
#
#   Any other photo (not a reply to a known message)
#     → save to TELEGRAM_RCLONE_DEST; triggers the file-processor OCR pipeline
#
# Tracks update cursor in /secrets/telegram/receipt-offset.txt.
# State (pending transactions, active splits) lives in /secrets/telegram/state.json.
#
# Example cron trigger (automations/cron/telegram-receipt-poll.md):
#
#   ---
#   cron: "* * * * *"
#   routine: telegram-receipt
#   TELEGRAM_RCLONE_DEST: nextcloud:S3/telegram
#   ---
#
# Credentials: /secrets/telegram/credentials.env
#   TELEGRAM_BOT_TOKEN=<your-bot-token>
#   TELEGRAM_CHAT_ID=<your-chat-id>

set -euo pipefail

message_file="${message_file:-}"
message_id="${message_id:-}"
message_dir="${message_dir:-}"
chain="${chain:-}"
seq="${seq:-}"

if [ "${DECREE_PRE_CHECK:-}" = "true" ]; then
    # shellcheck source=../lib/precheck.sh
    source "$(dirname "${BASH_SOURCE[0]}")/../lib/precheck.sh"
    command -v curl   >/dev/null 2>&1 || precheck_fail "telegram-receipt" "curl not found"
    command -v jq     >/dev/null 2>&1 || precheck_fail "telegram-receipt" "jq not found"
    command -v rclone >/dev/null 2>&1 || precheck_fail "telegram-receipt" "rclone not found"
    /work/.decree/lib/node_modules/.bin/tsx --version >/dev/null 2>&1 \
        || precheck_fail "telegram-receipt" "tsx not found"
    precheck_pass "telegram-receipt"
    exit 0
fi

# ── Configuration ─────────────────────────────────────────────────────────────

TELEGRAM_RCLONE_DEST="${TELEGRAM_RCLONE_DEST:-nextcloud:S3/telegram}"
_tg_creds="/secrets/telegram/credentials.env"
[ -f "$_tg_creds" ] && source "$_tg_creds"
[ -n "${TELEGRAM_BOT_TOKEN:-}" ] || { echo "TELEGRAM_BOT_TOKEN not set."; exit 1; }
[ -n "${TELEGRAM_CHAT_ID:-}"   ] || { echo "TELEGRAM_CHAT_ID not set."; exit 1; }

# shellcheck source=../lib/telegram.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/telegram.sh"

_state_file="/secrets/telegram/state.json"
[ -f "$_state_file" ] || echo '{"pending":{},"splits":{},"last_pending_message_id":null}' > "$_state_file"

_offset_file="/secrets/telegram/receipt-offset.txt"
_offset=0
[ -f "$_offset_file" ] && _offset=$(cat "$_offset_file")

_tsx="/work/.decree/lib/node_modules/.bin/tsx"
_ocr_prompt='Analyze this receipt and return ONLY a JSON object — no explanation, no markdown fences. Format:
{"items":[{"name":"string","amount":0.00}],"total":0.00}
Include every line item. Use negative amounts for discounts. "total" must match the receipt grand total.'

# ── Fetch updates ──────────────────────────────────────────────────────────────

echo "Polling (offset: $_offset)..."
_response=$(curl -sf \
    "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getUpdates?offset=${_offset}&limit=100&timeout=0")
_count=$(echo "$_response" | jq '.result | length')

if [ "$_count" -eq 0 ]; then
    echo "No new updates."
    exit 0
fi

echo "Updates: $_count"
_new_offset=$(echo "$_response" | jq '[.result[].update_id] | max + 1')

# ── Process each update ────────────────────────────────────────────────────────

for i in $(seq 0 $((_count - 1))); do
    _update=$(echo "$_response" | jq ".result[$i]")
    _reply_to=$(echo "$_update" | jq -r '.message.reply_to_message.message_id // empty')

    # ── Text "no" → revert split ──────────────────────────────────────────────
    _text_body=$(echo "$_update" | jq -r '.message.text // empty')
    if echo "$_text_body" | grep -qiE '^no\.?$'; then
        if [ -n "$_reply_to" ]; then
            _split_entry=$(jq -r --arg mid "$_reply_to" '.splits[$mid] // empty' "$_state_file")
            if [ -n "$_split_entry" ]; then
                _txn_id=$(echo "$_split_entry" | jq -r '.transaction_id')
                echo "Reverting split for transaction ${_txn_id}..."

                TXN_TRANSACTION_ID="$_txn_id" \
                    $_tsx /work/.decree/lib/actual-budget/revert-split.ts

                # Remove from splits state
                _updated=$(jq --arg mid "$_reply_to" 'del(.splits[$mid])' "$_state_file")
                echo "$_updated" > "$_state_file"

                telegram_send_reply "$_reply_to" "↩️ Split reverted. Transaction restored as a single entry."
                echo "Reverted split on ${_txn_id}."
                continue
            fi
        fi
        echo "Received 'no' but no matching split found — ignoring."
        continue
    fi

    # ── Photo message ─────────────────────────────────────────────────────────
    if ! echo "$_update" | jq -e '.message.photo' >/dev/null 2>&1; then
        continue
    fi

    _file_id=$(echo "$_update" | jq -r '.message.photo | last | .file_id')
    _timestamp=$(echo "$_update" | jq -r '.message.date')

    # Determine which pending transaction this receipt belongs to
    _pending_entry=""
    _notify_msg_id=""
    if [ -n "$_reply_to" ]; then
        _pending_entry=$(jq -r --arg mid "$_reply_to" '.pending[$mid] // empty' "$_state_file")
        _notify_msg_id="$_reply_to"
    fi
    if [ -z "$_pending_entry" ]; then
        _last_mid=$(jq -r '.last_pending_message_id // empty' "$_state_file")
        if [ -n "$_last_mid" ]; then
            _pending_entry=$(jq -r --arg mid "$_last_mid" '.pending[$mid] // empty' "$_state_file")
            _notify_msg_id="$_last_mid"
        fi
    fi

    # ── Receipt → split ───────────────────────────────────────────────────────
    if [ -n "$_pending_entry" ]; then
        _txn_id=$(echo "$_pending_entry" | jq -r '.transaction_id')
        _amount_cents=$(echo "$_pending_entry" | jq -r '.amount_cents')
        echo "Receipt for transaction ${_txn_id} (${_amount_cents} cents)..."

        _tmpfile=$(mktemp "/tmp/receipt.XXXXXX.jpg")
        trap 'rm -f "$_tmpfile"' EXIT
        telegram_download_file "$_file_id" "$_tmpfile"

        # OCR the receipt
        FILE_PATH="$_tmpfile" \
        OCR_MODEL="${OCR_MODEL:-llava}" \
        OLLAMA_URL="${OLLAMA_URL:-http://ollama:11434}" \
            _ocr_raw=$($_tsx /work/.decree/lib/ocr.ts "$_ocr_prompt") || {
                telegram_send_reply "$_notify_msg_id" "❌ OCR failed — could not read the receipt. Please try again."
                continue
            }

        # Extract JSON from OCR output (Ollama sometimes wraps it in prose)
        _json=$(echo "$_ocr_raw" | grep -oP '\{.*\}' | head -1 || true)
        if ! echo "$_json" | jq -e '.items and .total' >/dev/null 2>&1; then
            telegram_send_reply "$_notify_msg_id" "❌ Could not parse receipt as JSON. Please try a clearer photo."
            echo "OCR output was not parseable JSON: $_ocr_raw"
            continue
        fi

        # Validate: items must sum to total (within 2 cents for rounding)
        _items_sum=$(echo "$_json" | jq '[.items[].amount] | add // 0')
        _receipt_total=$(echo "$_json" | jq '.total')
        _diff=$(echo "$_items_sum $_receipt_total" | awk '{d=$1-$2; if(d<0)d=-d; printf "%d", d*100}')
        if [ "$_diff" -gt 2 ]; then
            telegram_send_reply "$_notify_msg_id" \
                "⚠️ Receipt items ($(printf '%.2f' "$_items_sum")) don't add up to total ($(printf '%.2f' "$_receipt_total")). Please try again."
            continue
        fi

        # Build splits JSON in cents
        _splits_json=$(echo "$_json" | jq '[.items[] | {name: .name, amount_cents: (.amount * 100 | round)}]')

        # Split the transaction
        TXN_TRANSACTION_ID="$_txn_id" \
        TXN_SPLITS_JSON="$_splits_json" \
            $_tsx /work/.decree/lib/actual-budget/split-transaction.ts || {
                telegram_send_reply "$_notify_msg_id" "❌ Failed to split transaction in Actual Budget."
                continue
            }

        # Build the reply breakdown message
        _n=$(echo "$_json" | jq '.items | length')
        _breakdown="✅ *Split into ${_n} items:*\n"
        while IFS= read -r item; do
            _name=$(echo "$item" | jq -r '.name')
            _amt=$(echo "$item" | jq -r '.amount')
            _breakdown="${_breakdown}• ${_name}: \$$(printf '%.2f' "$_amt")\n"
        done < <(echo "$_json" | jq -c '.items[]')
        _breakdown="${_breakdown}*Total: \$$(printf '%.2f' "$_receipt_total")* ✓\n\nReply _no_ to revert."

        _breakdown_msg_id=$(telegram_send_reply "$_notify_msg_id" "$(printf '%b' "$_breakdown")")

        # Update state: remove from pending, add to splits
        _updated=$(jq \
            --arg notify_mid "$_notify_msg_id" \
            --arg breakdown_mid "$_breakdown_msg_id" \
            --arg txn_id "$_txn_id" \
            'del(.pending[$notify_mid]) |
             .splits[$breakdown_mid] = {transaction_id: $txn_id}' \
            "$_state_file")
        echo "$_updated" > "$_state_file"
        echo "Split transaction ${_txn_id} into ${_n} items."

    else
        # ── Generic photo → rclone → file-processor pipeline ─────────────────
        _filename="${_timestamp}_${_file_id}.jpg"
        _dest="${TELEGRAM_RCLONE_DEST}/${_filename}"
        echo "Generic photo — saving to ${_dest}"

        curl -sf "$(telegram_get_file_url "$_file_id")" \
            | rclone rcat "$_dest" --config /secrets/rclone/rclone.conf
    fi
done

# ── Advance cursor ─────────────────────────────────────────────────────────────

mkdir -p "$(dirname "$_offset_file")"
echo "$_new_offset" > "$_offset_file"
echo "Done. Next offset: ${_new_offset}"
