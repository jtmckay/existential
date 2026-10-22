#!/usr/bin/env bash
# decree — Gmail → Actual Budget cron generator
#
# Walks through selecting a Gmail label, a parse script, and an Actual Budget
# account, then writes automation/cron/gmail-transactions-<label>.md.
#
# Run via: ./existential.sh run automation gmail-transactions-cron
# Requires: `./existential.sh run automation gmail-sync` + `./existential.sh run
#           decree gmail-labels` + `./existential.sh run actual-budget` first.

set -euo pipefail

# Self-elevate into existential-adhoc if we're on the host.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/src/utils/adhoc.sh"
adhoc_self_elevate "${BASH_SOURCE[0]}"

SECRETS_DIR="${SECRETS_DIR:-/secrets}"
LABELS_FILE="${SECRETS_DIR}/gmail/labels.json"
ACCOUNTS_FILE="${SECRETS_DIR}/actual-budget/accounts.json"
CRON_DIR="${DECREE_DIR:-/work/.decree}/cron"
PARSE_SCRIPTS_DIR="${PARSE_SCRIPTS_DIR:-/repo/automation/lib/actual-budget}"
DECREE_LIB_DIR="/work/.decree/lib/actual-budget"

hr() { printf '%0.s─' {1..56}; echo; }
die() { echo "Error: $*" >&2; exit 1; }

echo ""
echo "  Gmail → Actual Budget transaction cron setup"
hr
echo ""

[ -f "$LABELS_FILE" ]   || die "Gmail labels not found. Run: ./existential.sh run automation gmail-labels"
[ -f "$ACCOUNTS_FILE" ] || die "Actual Budget accounts not found. Run: ./existential.sh run actual-budget"

# ── Select Gmail label ────────────────────────────────────────────────────────

echo "  Gmail labels (custom only):"
echo ""

mapfile -t LABEL_NAMES < <(jq -r '.labels[] | select(.type == "user") | .name' "$LABELS_FILE")

if [ ${#LABEL_NAMES[@]} -eq 0 ]; then
    die "No custom labels found in ${LABELS_FILE}. Add labels in Gmail then run: ./existential.sh run automation gmail-labels"
fi

for i in "${!LABEL_NAMES[@]}"; do
    printf "    %d. %s\n" $(( i + 1 )) "${LABEL_NAMES[$i]}"
done
echo ""

read -rp "  Select label [1-${#LABEL_NAMES[@]}]: " sel
idx=$(( sel - 1 ))
[[ "$sel" =~ ^[0-9]+$ ]] && [ "$idx" -ge 0 ] && [ "$idx" -lt "${#LABEL_NAMES[@]}" ] \
    || die "Invalid selection."

GMAIL_LABEL="${LABEL_NAMES[$idx]}"
echo "  Selected label: ${GMAIL_LABEL}"
echo ""

_label_slug=$(printf '%s' "$GMAIL_LABEL" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '_' | sed 's/_*$//')
CRON_FILE="${CRON_DIR}/gmail-transactions-${_label_slug}.md"

# ── Select parse script ───────────────────────────────────────────────────────

echo "  Parse scripts:"
echo ""

mapfile -t PARSE_SCRIPTS < <(find "$PARSE_SCRIPTS_DIR" -maxdepth 1 -name 'parse-*.ts' -type f | sort | xargs -I{} basename {})

if [ ${#PARSE_SCRIPTS[@]} -eq 0 ]; then
    die "No parse-*.ts scripts found in ${PARSE_SCRIPTS_DIR}."
fi

for i in "${!PARSE_SCRIPTS[@]}"; do
    printf "    %d. %s\n" $(( i + 1 )) "${PARSE_SCRIPTS[$i]}"
done
echo ""

read -rp "  Select parse script [1-${#PARSE_SCRIPTS[@]}]: " sel
idx=$(( sel - 1 ))
[[ "$sel" =~ ^[0-9]+$ ]] && [ "$idx" -ge 0 ] && [ "$idx" -lt "${#PARSE_SCRIPTS[@]}" ] \
    || die "Invalid selection."

PARSE_SCRIPT_NAME="${PARSE_SCRIPTS[$idx]}"
PARSE_SCRIPT_PATH="${DECREE_LIB_DIR}/${PARSE_SCRIPT_NAME}"
echo "  Selected: ${PARSE_SCRIPT_NAME}"
echo ""

# ── Select Actual Budget account ──────────────────────────────────────────────

echo "  Actual Budget accounts:"
echo ""

mapfile -t ACCOUNT_NAMES < <(jq -r '.[] | select(.closed | not) | .name' "$ACCOUNTS_FILE")
mapfile -t ACCOUNT_IDS   < <(jq -r '.[] | select(.closed | not) | .id'   "$ACCOUNTS_FILE")

if [ ${#ACCOUNT_NAMES[@]} -eq 0 ]; then
    die "No open accounts found in ${ACCOUNTS_FILE}."
fi

for i in "${!ACCOUNT_NAMES[@]}"; do
    printf "    %d. %s\n" $(( i + 1 )) "${ACCOUNT_NAMES[$i]}"
done
echo ""

read -rp "  Select account [1-${#ACCOUNT_NAMES[@]}]: " sel
idx=$(( sel - 1 ))
[[ "$sel" =~ ^[0-9]+$ ]] && [ "$idx" -ge 0 ] && [ "$idx" -lt "${#ACCOUNT_NAMES[@]}" ] \
    || die "Invalid selection."

ACCOUNT_NAME="${ACCOUNT_NAMES[$idx]}"
ACCOUNT_ID="${ACCOUNT_IDS[$idx]}"
echo "  Selected account: ${ACCOUNT_NAME} (${ACCOUNT_ID})"
echo ""

# ── Select schedule ───────────────────────────────────────────────────────────

read -rp "  Cron schedule [*/5 * * * *]: " INPUT_CRON
CRON_SCHEDULE="${INPUT_CRON:-*/5 * * * *}"

# ── Write cron file ───────────────────────────────────────────────────────────

if [ -f "$CRON_FILE" ]; then
    read -rp "  ${CRON_FILE##"$REPO_DIR/"} already exists. Replace? (y/N): " answer
    [[ "${answer,,}" == "y" ]] || { echo "Skipping."; exit 0; }
fi

# YAML single quotes: a label may hold a colon or a quote, and '' is the one
# escape single-quoted YAML has.
_q() { printf "'%s'" "${1//\'/\'\'}"; }

cat > "$CRON_FILE" << EOF
---
cron: "${CRON_SCHEDULE}"
machine: gmail_sync
params:
  GMAIL_LABEL_FILTER: $(_q "$GMAIL_LABEL")
  GMAIL_ROUTINE: actual_budget_parse
  # Its own sync cursor, so gmail-sync on the same label does not share one.
  GMAIL_HISTORY_KEY: transactions-${_label_slug}
  GMAIL_FORWARD: |
    parse_script=${PARSE_SCRIPT_PATH}
    account_id=${ACCOUNT_ID}
---

Fetch transaction alert emails from label '${GMAIL_LABEL}' and route each to
actual_budget_parse for import into Actual Budget (${ACCOUNT_NAME}).
EOF

echo ""
hr
echo ""
echo "  Created: automation/cron/gmail-transactions-${_label_slug}.md"
echo "  Label:   ${GMAIL_LABEL}"
echo "  Parser:  ${PARSE_SCRIPT_NAME}"
echo "  Account: ${ACCOUNT_NAME}"
echo ""
echo "  The cron will fire on schedule '${CRON_SCHEDULE}' automatically."
echo "  No restart needed — Decree picks up new cron files on next tick."
echo ""
