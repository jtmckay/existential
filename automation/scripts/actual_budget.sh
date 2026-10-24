#!/usr/bin/env bash
# actual_budget
#
# Posts a transaction to Actual Budget using @actual-app/api. The details are
# the params; the body is the amount in decimal dollars (negative = expense,
# positive = income):
#
#   decree emit --machine actual_budget --param account_id=abc123-... \
#       --param payee_name='Whole Foods' --param notes='Weekly groceries' <<<'-87.43'

set -euo pipefail

TSX=/work/.decree/lib/node_modules/.bin/tsx
[ -f /secrets/actual-budget/credentials.env ] && [ -x "$TSX" ] \
    || { echo "Actual Budget is not set up — run: ./existential.sh run actual-budget" >&2; exit 1; }

account_id="$DECREE_DATA_ACCOUNT_ID"
payee_name="$DECREE_DATA_PAYEE_NAME"
date="${DECREE_DATA_DATE:-$(date +%Y-%m-%d)}"
notes="$DECREE_DATA_NOTES"
category_id="$DECREE_DATA_CATEGORY_ID"

[ -n "$account_id" ] || { echo "Missing account_id param."; exit 1; }
[ -n "$payee_name" ] || { echo "Missing payee_name param."; exit 1; }

# ── Extract amount from message body ─────────────────────────────────────────

amount_raw=$(awk '
    NR==1 && /^---$/ { skip=1; next }
    skip && /^---$/  { skip=0; next }
    !skip
' "$DECREE_MESSAGE" | sed '/./,$!d' | head -1 | tr -d '[:space:]')

[ -n "$amount_raw" ] || { echo "Missing amount in message body."; exit 1; }

# ── Post transaction ──────────────────────────────────────────────────────────

TXN_ACCOUNT_ID="$account_id" \
TXN_PAYEE_NAME="$payee_name" \
TXN_DATE="$date" \
TXN_NOTES="$notes" \
TXN_CATEGORY_ID="$category_id" \
TXN_AMOUNT="$amount_raw" \
    "$TSX" "$DECREE_LIB/actual-budget/post-transaction.ts"

echo "Posted ${amount_raw} → ${payee_name} (account: ${account_id})"
