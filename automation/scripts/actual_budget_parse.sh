#!/usr/bin/env bash
# actual_budget_parse
#
# Runs a parse script against one email from gmail_sync and emits actual_budget
# when the script returns a transaction.
#
# The parse script reads the email's headers from its environment (subject,
# date, from, to — exported below from this machine's params) and must output
# a JSON object to stdout:
#   { "amount": "-45.23", "payee": "STARBUCKS", "date": "2024-01-15", "notes": "..." }
# Exit 0 with no output to skip (not a transaction). Exit non-zero on error.
#
# parse_script and account_id arrive through gmail_sync's GMAIL_FORWARD:
#
#   ---
#   cron: "*/5 * * * *"
#   machine: gmail_sync
#   params:
#     GMAIL_LABEL_FILTER: MyBank/Transactions
#     GMAIL_ROUTINE: actual_budget_parse
#     GMAIL_FORWARD: |
#       parse_script=/work/.decree/lib/actual-budget/parse-chase.ts
#       account_id=dedddddd-2222-4444-9999-111111cccccc
#   ---

set -euo pipefail

TSX=/work/.decree/lib/node_modules/.bin/tsx
[ -x "$TSX" ] || { echo "tsx not installed — run: ./existential.sh run actual-budget" >&2; exit 1; }

parse_script="$DECREE_DATA_PARSE_SCRIPT"
account_id="$DECREE_DATA_ACCOUNT_ID"

[ -n "$parse_script" ] || { echo "Missing parse_script param."; exit 1; }
[ -n "$account_id" ]   || { echo "Missing account_id param."; exit 1; }
[ -f "$parse_script" ] || { echo "parse_script not found: ${parse_script}"; exit 1; }

export subject="$DECREE_DATA_SUBJECT" date="$DECREE_DATA_DATE" \
       from="$DECREE_DATA_FROM" to="$DECREE_DATA_TO"

# ── Run parser ────────────────────────────────────────────────────────────────

result=$("$TSX" "$parse_script")

# Empty output = not a transaction, skip cleanly
if [ -z "$result" ]; then
    echo "Parser returned no output — not a transaction, skipping."
    exit 0
fi

# ── Extract fields ────────────────────────────────────────────────────────────

amount=$(printf '%s' "$result" | jq -r '.amount // empty')
payee=$(printf '%s'  "$result" | jq -r '.payee  // empty')
txn_date=$(printf '%s' "$result" | jq -r '.date  // empty')
notes=$(printf '%s'  "$result" | jq -r '.notes  // empty')

if [ -z "$amount" ] || [ -z "$payee" ]; then
    echo "Parser output missing required fields (amount, payee): ${result}"
    exit 1
fi

[ -n "$txn_date" ] || txn_date=$(date +%Y-%m-%d)

decree emit --machine actual_budget --param account_id="$account_id" \
    --param payee_name="$payee" --param date="$txn_date" --param notes="$notes" \
    >/dev/null <<<"$amount"

echo "Queued transaction: ${amount} → ${payee} (${txn_date})"
