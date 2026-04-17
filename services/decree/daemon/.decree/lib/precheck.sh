#!/usr/bin/env bash
# Pre-check helpers
#
# Source inside DECREE_PRE_CHECK blocks:
#   source "$(dirname "${BASH_SOURCE[0]}")/../lib/precheck.sh"
#
# Then use:
#   precheck_pass "routine-name"
#   precheck_fail "routine-name" "reason"
#
# All results are written to PRECHECK_LOG (default: /work/.decree/precheck.log)
# so every routine's pass/fail is visible in one place after a daemon restart.

PRECHECK_LOG="${PRECHECK_LOG:-/work/.decree/precheck.log}"

precheck_pass() {
    local routine="$1"
    printf '[%s] %-14s OK\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$routine" >> "$PRECHECK_LOG"
}

precheck_fail() {
    local routine="$1" msg="$2"
    local line
    line="$(printf '[%s] %-14s FAIL: %s' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$routine" "$msg")"
    printf '%s\n' "$line" >&2
    printf '%s\n' "$line" >> "$PRECHECK_LOG"
    exit 1
}
