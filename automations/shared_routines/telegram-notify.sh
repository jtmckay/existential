#!/usr/bin/env bash
# Telegram Notify
#
# Sends a Telegram message for a new Actual Budget transaction and records it
# in the pending-receipts state so the user can reply with a receipt photo to
# split the transaction.
#
# Enqueued automatically by actual-budget when /secrets/telegram/credentials.env
# is present and contains TELEGRAM_BOT_TOKEN + TELEGRAM_CHAT_ID.
#
# Required frontmatter:
#   transaction_id  — Actual Budget transaction UUID
#   account_id      — Actual Budget account UUID
#   amount_cents    — integer cents (negative = expense)
#   payee_name      — payee string
#   date            — YYYY-MM-DD
#
# Optional frontmatter:
#   notes           — transaction memo

set -euo pipefail

message_file="${message_file:-}"
message_id="${message_id:-}"
message_dir="${message_dir:-}"
chain="${chain:-}"
seq="${seq:-}"

if [ "${DECREE_PRE_CHECK:-}" = "true" ]; then
    # shellcheck source=../lib/precheck.sh
    source "$(dirname "${BASH_SOURCE[0]}")/../lib/precheck.sh"
    command -v curl >/dev/null 2>&1 || precheck_fail "telegram-notify" "curl not found"
    command -v jq   >/dev/null 2>&1 || precheck_fail "telegram-notify" "jq not found"
    precheck_pass "telegram-notify"
    exit 0
fi

# ── Configuration ─────────────────────────────────────────────────────────────

_tg_creds="/secrets/telegram/credentials.env"
[ -f "$_tg_creds" ] && source "$_tg_creds"
[ -n "${TELEGRAM_BOT_TOKEN:-}" ] || { echo "TELEGRAM_BOT_TOKEN not set."; exit 1; }
[ -n "${TELEGRAM_CHAT_ID:-}"   ] || { echo "TELEGRAM_CHAT_ID not set."; exit 1; }

# shellcheck source=../lib/telegram.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/telegram.sh"

_state_file="/secrets/telegram/state.json"
[ -f "$_state_file" ] || echo '{"pending":{},"splits":{},"last_pending_message_id":null}' > "$_state_file"

# ── Frontmatter params ────────────────────────────────────────────────────────

transaction_id="${transaction_id:-}"
account_id="${account_id:-}"
amount_cents="${amount_cents:-0}"
payee_name="${payee_name:-Unknown}"
date="${date:-}"
notes="${notes:-}"

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
