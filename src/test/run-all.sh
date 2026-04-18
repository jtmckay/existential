#!/usr/bin/env bash
# Run all tests in src/test/ and report results.
# Invoked by: ./existential.sh test

set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PASS=0
FAIL=0

run_test() {
    local name="$1"
    local script="${TEST_DIR}/test-${name}.sh"

    printf "  %-16s " "$name"

    if [ ! -f "$script" ]; then
        echo "SKIP"
        return
    fi

    local output
    if output=$(bash "$script" 2>&1); then
        echo "PASS"
        ((PASS++))
    else
        echo "FAIL"
        ((FAIL++))
        echo "$output" | sed 's/^/    /'
    fi
}

echo ""
echo "=== Existential Test Suite ==="
echo ""

run_test "syntax"
run_test "gmail"
run_test "rclone"
run_test "ntfy"

echo ""
echo "Results: ${PASS} passed, ${FAIL} failed"
echo ""

[ "$FAIL" -eq 0 ]
