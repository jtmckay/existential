#!/usr/bin/env bash
# Telegram Notify
#
# Sends a Telegram message for a new Actual Budget transaction and records it
# in the pending-receipts state so the user can reply with a receipt photo to
# split the transaction.
#
# Emitted by actual_budget when /secrets/telegram/credentials.env is present
# and contains TELEGRAM_BOT_TOKEN + TELEGRAM_CHAT_ID. The transaction's details
# are the params.

set -euo pipefail

# ── Configuration ─────────────────────────────────────────────────────────────

_tg_creds="/secrets/telegram/credentials.env"
# shellcheck source=/dev/null  # runtime path, contents are credentials
[ -f "$_tg_creds" ] && source "$_tg_creds"
[ -n "${TELEGRAM_BOT_TOKEN:-}" ] || { echo "TELEGRAM_BOT_TOKEN not set."; exit 1; }
[ -n "${TELEGRAM_CHAT_ID:-}"   ] || { echo "TELEGRAM_CHAT_ID not set."; exit 1; }

# shellcheck source=../lib/telegram.sh
source "${DECREE_LIB}/telegram.sh"

_state_file="/secrets/telegram/state.json"
[ -f "$_state_file" ] || echo '{"pending":{},"splits":{},"last_pending_message_id":null}' > "$_state_file"

# ── Params ────────────────────────────────────────────────────────────────────

transaction_id="$DECREE_DATA_TRANSACTION_ID"
account_id="$DECREE_DATA_ACCOUNT_ID"
amount_cents="$DECREE_DATA_AMOUNT_CENTS"
payee_name="$DECREE_DATA_PAYEE_NAME"
date="$DECREE_DATA_DATE"
notes="$DECREE_DATA_NOTES"

[ -n "$transaction_id" ] || { echo "transaction_id is required."; exit 1; }

# ── Format and send ───────────────────────────────────────────────────────────

_dollars=$(echo "$amount_cents" | awk '{printf "%.2f", $1 / 100}')
_abs_dollars=$(echo "$_dollars" | sed 's/^-//')
_sign=$([ "$amount_cents" -lt 0 ] && echo "-" || echo "+")

_text="💳 *${_sign}\$${_abs_dollars}* at *${payee_name}*"
[ -n "$date"  ] && _text="${_text} on ${date}"
[ -n "$notes" ] && _text="${_text}\n_${notes}_"
_text="${_text}\n\nReply with a receipt photo to split this transaction."

_msg_id=$(telegram_send_message "$TELEGRAM_CHAT_ID" "$(printf '%b' "$_text")")
echo "Sent Telegram notification (message_id: ${_msg_id})"

# ── Update state ──────────────────────────────────────────────────────────────

_updated=$(jq \
    --arg mid "$_msg_id" \
    --arg tid "$transaction_id" \
    --arg aid "$account_id" \
    --argjson cents "$amount_cents" \
    --arg payee "$payee_name" \
    --arg date "$date" \
    --arg notes "$notes" \
    '.pending[$mid] = {
        transaction_id: $tid,
        account_id: $aid,
        amount_cents: $cents,
        payee_name: $payee,
        date: $date,
        notes: $notes
    } | .last_pending_message_id = $mid' \
    "$_state_file")

echo "$_updated" > "$_state_file"
echo "State updated. Pending message_id: ${_msg_id}"
