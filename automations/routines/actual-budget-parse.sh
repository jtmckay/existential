#!/usr/bin/env bash
# actual-budget-parse
#
# Generic routine: runs a parse script against the current message and writes
# an actual-budget outbox message if the script returns a transaction.
#
# The parse script receives all decree message env vars (subject, date, etc.)
# and must output a JSON object to stdout:
#   { "amount": "-45.23", "payee": "STARBUCKS", "date": "2024-01-15", "notes": "..." }
# Exit 0 with no output to skip (not a transaction). Exit non-zero on error.
#
# Required frontmatter / params:
#   parse_script  — container path to the tsx parser, e.g.
#                   /work/.decree/lib/actual-budget/parse-chase.ts
#   account_id    — Actual Budget account UUID
#
# Example cron trigger (automations/cron/gmail-transactions-<label>.md):
#
#   ---
#   cron: "*/5 * * * *"
#   routine: gmail-sync
#   GMAIL_LABEL_FILTER: MyBank/Transactions
#   GMAIL_ROUTINE: actual-budget-parse
#   fwd_parse_script: /work/.decree/lib/actual-budget/parse-chase.ts
#   fwd_account_id: dedddddd-2222-4444-9999-111111cccccc
#   ---

set -euo pipefail

message_file="${message_file:-}"
message_id="${message_id:-}"
message_dir="${message_dir:-}"
chain="${chain:-}"
seq="${seq:-}"

if [ "${DECREE_PRE_CHECK:-}" = "true" ]; then
    # shellcheck source=../lib/precheck.sh
    source "$(dirname "${BASH_SOURCE[0]}")/../lib/precheck.sh"
    command -v jq >/dev/null 2>&1 \
        || precheck_fail "actual-budget-parse" "jq not found"
    /work/.decree/lib/node_modules/.bin/tsx --version >/dev/null 2>&1 \
        || precheck_fail "actual-budget-parse" "tsx not installed — run: ./existential.sh setup actual-budget"
    precheck_pass "actual-budget-parse"
    exit 0
fi

# ── Custom params ─────────────────────────────────────────────────────────────

parse_script="${parse_script:-}"
account_id="${account_id:-}"

[ -n "$parse_script" ] || { echo "Missing parse_script param."; exit 1; }
[ -n "$account_id" ]   || { echo "Missing account_id param."; exit 1; }
[ -f "$parse_script" ] || { echo "parse_script not found: ${parse_script}"; exit 1; }

# ── Run parser ────────────────────────────────────────────────────────────────

result=$(/work/.decree/lib/node_modules/.bin/tsx "$parse_script")

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

# ── YAML value escaping ───────────────────────────────────────────────────────

yaml_str() { printf '%s' "${1:-}" | tr -d '\r' | tr '\n' ' ' | sed "s/'/''/g"; }

# ── Write outbox message for actual-budget ────────────────────────────────────

OUTBOX_DIR="${OUTBOX_DIR:-/work/.decree/outbox}"
mkdir -p "$OUTBOX_DIR"
outfile="${OUTBOX_DIR}/actual-budget-$(date +%s%N).md"

{
    printf -- '---\n'
    printf 'routine: actual-budget\n'
    printf "account_id: '%s'\n" "$(yaml_str "$account_id")"
    printf "payee_name: '%s'\n" "$(yaml_str "$payee")"
    printf "date: '%s'\n"       "$(yaml_str "$txn_date")"
    printf "notes: '%s'\n"      "$(yaml_str "$notes")"
    printf -- '---\n'
    printf '%s\n' "$amount"
} > "$outfile"

echo "Queued transaction: ${amount} → ${payee} (${txn_date})"
