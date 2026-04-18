#!/usr/bin/env bash
# Syntax-check every .sh file in /src.

set -euo pipefail

FAIL=0

while IFS= read -r -d '' script; do
    if ! bash -n "$script" 2>/dev/null; then
        echo "SYNTAX ERROR: $script"
        bash -n "$script" 2>&1 | sed 's/^/  /'
        ((FAIL++))
    fi
done < <(find /src -name "*.sh" -print0 | sort -z)

if [ "$FAIL" -gt 0 ]; then
    echo "$FAIL script(s) have syntax errors" >&2
    exit 1
fi

echo "All scripts pass syntax check"
