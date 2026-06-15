#!/usr/bin/env bash
# Check Disabled Runs
#
# Scans run directories from the last 24 hours (configurable via window_minutes)
# and reports any that have a message.md but no routine.log — indicating the
# routine was disabled or failed resolution when the cron fired. Exits non-zero
# so the failure surfaces in the dashboard via the afterEach hook.
set -euo pipefail

if [ "${DECREE_PRE_CHECK:-}" = "true" ]; then
    # shellcheck source=../lib/precheck.sh
    source "$(dirname "${BASH_SOURCE[0]}")/../lib/precheck.sh"
    precheck_pass "check-disabled-runs"
    exit 0
fi

RUNS_DIR="${RUNS_DIR:-/work/.decree/runs}"
window_minutes="${window_minutes:-1440}"

disabled=()

while IFS= read -r -d '' dir; do
    [ -f "${dir}/message.md" ] || continue
    [ -f "${dir}/routine.log" ] && continue
    [ -f "${dir}/run.json" ]    && continue
    disabled+=("$(basename "$dir")")
done < <(find "$RUNS_DIR" -maxdepth 1 -mindepth 1 -type d \
    -not -name "archive" \
    -mmin +5 \
    -mmin "-${window_minutes}" \
    -print0 2>/dev/null | sort -z)

if [ ${#disabled[@]} -eq 0 ]; then
    echo "No disabled-routine runs in the last ${window_minutes} minutes."
    exit 0
fi

echo "ERROR: ${#disabled[@]} run(s) fired with no routine.log (routine disabled or failed resolution):"
for run in "${disabled[@]}"; do
    routine=$(grep -m1 '^routine:' "${RUNS_DIR}/${run}/message.md" 2>/dev/null \
        | sed 's/^routine:[[:space:]]*//' || echo "unknown")
    echo "  ${run}  (routine: ${routine})"
done
exit 1
