#!/usr/bin/env bash
# Clean Runs
#
# Removes old run directories for cron routines, keeping only the
# most recent 10 runs per routine. Adhoc runs are left untouched.
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

# Discover cron routines dynamically from cron directory.
# Routine names like "notes/compile-notes" become "compile-notes" in run dirs.
CRON_ROUTINES=()
for cronfile in "$CRON_DIR"/*.md; do
    [ -f "$cronfile" ] || continue
    routine=$(sed -n 's/^routine: *//p' "$cronfile")
    [ -n "$routine" ] || continue
    # Use basename of routine path (notes/compile-notes → compile-notes)
    CRON_ROUTINES+=("${routine##*/}")
done

if [ ${#CRON_ROUTINES[@]} -eq 0 ]; then
    echo "No cron routines found."
    exit 0
fi

total_removed=0

for routine in "${CRON_ROUTINES[@]}"; do
    # Match directories containing -<routine>-
    dirs=()
    while IFS= read -r -d '' d; do
        dirs+=("$d")
    done < <(find "$RUNS_DIR" -maxdepth 1 -type d -name "*-${routine}-*" -print0 2>/dev/null | sort -z)

    count=${#dirs[@]}
    if [ "$count" -le "$KEEP" ]; then
        continue
    fi

    remove=$(( count - KEEP ))
    for (( i=0; i<remove; i++ )); do
        rm -rf "${dirs[$i]}"
        total_removed=$(( total_removed + 1 ))
    done
    echo "  ${routine}: removed ${remove}, kept ${KEEP}"
done

echo "Cleaned ${total_removed} run(s)."
