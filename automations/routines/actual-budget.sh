#!/usr/bin/env bash
# actual-budget
#
# Posts a transaction to Actual Budget using @actual-app/api.
# Transaction details come from message frontmatter; the body is the amount in
# decimal dollars (negative = expense, positive = income).
#
# Required frontmatter fields:
#   account_id   — Actual Budget account UUID
#   payee_name   — Payee name string
#
# Optional frontmatter fields:
#   date         — YYYY-MM-DD (defaults to today)
#   notes        — Memo/notes string
#   category_id  — Actual Budget category UUID
#
# Example inbox message:
#
#   ---
#   routine: actual-budget
#   account_id: 'abc123-...'
#   payee_name: 'Whole Foods'
#   date: '2024-01-15'
#   notes: 'Weekly groceries'
#   category_id: ''
#   ---
#   -87.43

set -euo pipefail

message_file="${message_file:-}"

if [ "${DECREE_PRE_CHECK:-}" = "true" ]; then
    # shellcheck source=../lib/precheck.sh
    source "$(dirname "${BASH_SOURCE[0]}")/../lib/precheck.sh"
    command -v node >/dev/null 2>&1 \
        || precheck_fail "actual-budget" "node not found"
    [ -f "/secrets/actual-budget/credentials.env" ] \
        || precheck_fail "actual-budget" "credentials missing — run: ./existential.sh setup actual-budget"
    /work/.decree/lib/node_modules/.bin/tsx --version >/dev/null 2>&1 \
        || precheck_fail "actual-budget" "tsx not installed — run: ./existential.sh setup actual-budget"
    precheck_pass "actual-budget"
    exit 0
fi

# ── Read frontmatter fields ───────────────────────────────────────────────────

account_id="${account_id:-}"
payee_name="${payee_name:-}"
date="${date:-$(date +%Y-%m-%d)}"
notes="${notes:-}"
category_id="${category_id:-}"

[ -n "$account_id" ] || { echo "Missing account_id in frontmatter."; exit 1; }
[ -n "$payee_name" ] || { echo "Missing payee_name in frontmatter."; exit 1; }

# ── Extract amount from message body ─────────────────────────────────────────

amount_raw=$(awk '
    NR==1 && /^---$/ { skip=1; next }
    skip && /^---$/  { skip=0; next }
    !skip
' "$message_file" | sed '/./,$!d' | head -1 | tr -d '[:space:]')

[ -n "$amount_raw" ] || { echo "Missing amount in message body."; exit 1; }

# ── Post transaction ──────────────────────────────────────────────────────────

_post_output=$(TXN_ACCOUNT_ID="$account_id" \
TXN_PAYEE_NAME="$payee_name" \
TXN_DATE="$date" \
TXN_NOTES="$notes" \
TXN_CATEGORY_ID="$category_id" \
TXN_AMOUNT="$amount_raw" \
    /work/.decree/lib/node_modules/.bin/tsx /work/.decree/lib/actual-budget/post-transaction.ts)
echo "$_post_output"

echo "Posted ${amount_raw} → ${payee_name} (account: ${account_id})"

# ── Sidecar: Telegram notification (optional) ─────────────────────────────────
# Fires only when /secrets/telegram/credentials.env exists and TELEGRAM_CHAT_ID is set.

_tg_creds="/secrets/telegram/credentials.env"
if [ -f "$_tg_creds" ]; then
    source "$_tg_creds"
    if [ -n "${TELEGRAM_BOT_TOKEN:-}" ] && [ -n "${TELEGRAM_CHAT_ID:-}" ]; then
        _txn_id=$(echo "$_post_output" | grep -oP '(?<=\(id: )[^)]+' || true)
        if [ -n "$_txn_id" ]; then
            # Convert cents to dollars for display (amount_raw is decimal dollars)
            _amount_cents=$(echo "$amount_raw" | awk '{printf "%d", $1 * 100}')
            _outbox_file="/work/.decree/outbox/telegram-notify-$(date +%s%N).md"
            cat > "$_outbox_file" << EOF
---
routine: telegram-notify
transaction_id: '${_txn_id}'
account_id: '${account_id}'
amount_cents: ${_amount_cents}
payee_name: '${payee_name}'
date: '${date}'
notes: '${notes}'
---
EOF
            echo "Queued Telegram notification for transaction ${_txn_id}."
        fi
    fi
fi
