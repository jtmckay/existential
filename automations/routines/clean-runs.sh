#!/usr/bin/env bash
# Clean Runs
#
# Removes old run directories for cron routines, keeping only the
# most recent 10 runs per routine. Adhoc runs are left untouched.
#
# Example cron trigger (.decree/cron/clean-runs.md):
#
#   ---
#   cron: "0 4 * * *"
#   routine: clean-runs
#   keep: 10
#   ---
set -euo pipefail

if [ "${DECREE_PRE_CHECK:-}" = "true" ]; then
    # shellcheck source=../lib/precheck.sh
    source "$(dirname "${BASH_SOURCE[0]}")/../lib/precheck.sh"
    precheck_pass "clean-runs"
    exit 0
fi

# --- Configuration ---
RUNS_DIR="${RUNS_DIR:-/work/.decree/runs}"
CRON_DIR="${CRON_DIR:-/work/.decree/cron}"
KEEP="${keep:-10}"

# Run dirs are named after the cron file basename (not the routine name).
# e.g. cron/gmail-transactions-jtmckay_chase_transaction.md → *-gmail-transactions-jtmckay_chase_transaction-*
CRON_TRIGGERS=()
for cronfile in "$CRON_DIR"/*.md; do
    [ -f "$cronfile" ] || continue
    trigger=$(basename "$cronfile" .md)
    CRON_TRIGGERS+=("$trigger")
done

if [ ${#CRON_TRIGGERS[@]} -eq 0 ]; then
    echo "No cron triggers found."
    exit 0
fi

total_removed=0

for trigger in "${CRON_TRIGGERS[@]}"; do
    # Match directories named *-<trigger>-<attempt>
    dirs=()
    while IFS= read -r -d '' d; do
        dirs+=("$d")
    done < <(find "$RUNS_DIR" -maxdepth 1 -type d -name "*-${trigger}-*" -print0 2>/dev/null | sort -z)

    count=${#dirs[@]}
    if [ "$count" -le "$KEEP" ]; then
        continue
    fi

    remove=$(( count - KEEP ))
    for (( i=0; i<remove; i++ )); do
        rm -rf "${dirs[$i]}"
        total_removed=$(( total_removed + 1 ))
    done
    echo "  ${trigger}: removed ${remove}, kept ${KEEP}"
done

echo "Cleaned ${total_removed} run(s)."
