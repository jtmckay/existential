#!/usr/bin/env bash
# Syntax-check every .sh file in /src and every service-dir exist.*.sh.

set -euo pipefail

FAIL=0

check_script() {
    local script="$1"
    if ! bash -n "$script" 2>/dev/null; then
        echo "SYNTAX ERROR: $script"
        bash -n "$script" 2>&1 | sed 's/^/  /'
        FAIL=$((FAIL + 1))
    fi
}

while IFS= read -r -d '' script; do
    check_script "$script"
done < <(find /src -name "*.sh" -print0 2>/dev/null | sort -z)

while IFS= read -r -d '' script; do
    check_script "$script"
done < <(find /repo/ai /repo/services /repo/hosting /repo/nas \
              -maxdepth 2 -name 'exist.*.sh' -type f -print0 2>/dev/null | sort -z)

# Self-check canary: TEST_SELFCHECK=1 forces a failure so this suite's own
# FAIL→non-zero-exit path is itself testable (src/test/run-all.sh selfcheck).
[[ "${TEST_SELFCHECK:-}" == 1 ]] && FAIL=$((FAIL + 1))

if [ "$FAIL" -gt 0 ]; then
    echo "$FAIL script(s) have syntax errors" >&2
    exit 1
fi

echo "All scripts pass syntax check"
