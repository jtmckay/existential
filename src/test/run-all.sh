#!/usr/bin/env bash
# run-all.sh — orchestrate the existential test suite.
#
# Usage: run-all.sh [unit|integration|all]
#   unit        — only src/test/unit/ (no live services needed)
#   integration — only src/test/integration/ (live credentials/containers)
#   all         — unit + integration + per-service exist.test.sh (default)
#
# Invoked by `./existential.sh test`. Runs inside the existential-adhoc
# container, so /repo points at the repo root and container DNS resolves on
# the `exist` network — see CLAUDE.md "Service test scripts" + Networking.

set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="${REPO_DIR:-/repo}"
TIER="${1:-all}"   # unit | integration | all

# Color support — only when stdout is a TTY
GREEN=''; RED=''; RESET=''
[[ -t 1 ]] && { GREEN=$'\033[0;32m'; RED=$'\033[0;31m'; RESET=$'\033[0m'; }

PASS=0; FAIL=0; SKIP=0
FAIL_NAMES=(); SKIP_NAMES=()

# Colorize PASS/FAIL marker lines from individual test scripts.
colorize() {
    while IFS= read -r line; do
        case "$line" in
            "  PASS  "*) printf "  %s✓%s %s\n" "$GREEN" "$RESET" "${line#  PASS  }" ;;
            "  FAIL  "*) printf "  %s✗%s %s\n" "$RED"   "$RESET" "${line#  FAIL  }" ;;
            *)           printf '%s\n' "$line" ;;
        esac
    done
}

run() {
    local label="$1" script="$2"
    local output rc=0
    output=$(bash "$script" 2>&1) || rc=$?
    if [ "$rc" -ne 0 ]; then
        printf '%s✗%s %s\n' "$RED" "$RESET" "$label"
        printf '%s\n' "$output" | colorize
        FAIL=$((FAIL + 1))
        FAIL_NAMES+=("$label")
    elif printf '%s\n' "$output" | grep -q 'skipped — '; then
        SKIP=$((SKIP + 1))
        SKIP_NAMES+=("$label")
    else
        printf '%s✓%s %s\n' "$GREEN" "$RESET" "$label"
        printf '%s\n' "$output" | colorize
        PASS=$((PASS + 1))
    fi
}

# ── Self-check: every unit suite must FAIL when an assertion fails ──────────────
# Runs each suite with TEST_SELFCHECK=1, which trips a deliberate canary failure
# inside the suite. A suite that still exits 0 has a broken FAIL→exit path and is
# manufacturing false confidence — the exact rot this whole effort targets.
if [[ "$TIER" == "selfcheck" ]]; then
    echo "=== Suite self-check (a forced assertion must fail each suite) ==="
    sc_fail=0
    for script in "${TEST_DIR}/unit/test-"*.sh; do
        [ -f "$script" ] || continue
        t=$(basename "$script" .sh); t="${t#test-}"
        rc=0
        out=$(TEST_SELFCHECK=1 bash "$script" 2>&1) || rc=$?   # || rc=$? so set -e doesn't abort the loop
        if printf '%s\n' "$out" | grep -q 'skipped — '; then
            printf '  - %s (skipped — not exercised in this environment)\n' "$t"
        elif [ "$rc" -ne 0 ]; then
            printf '%s✓%s %s — fails as expected under a forced assertion\n' "$GREEN" "$RESET" "$t"
        else
            printf '%s✗%s %s — SWALLOWED a forced assertion (exited 0)\n' "$RED" "$RESET" "$t"
            sc_fail=$((sc_fail + 1))
        fi
    done
    echo ""
    if [ "$sc_fail" -ne 0 ]; then
        echo "=== Self-check FAILED: ${sc_fail} suite(s) do not surface assertion failures ==="
        exit 1
    fi
    echo "=== Self-check passed: every unit suite surfaces a failed assertion ==="
    exit 0
fi

# ── Unit tests ─────────────────────────────────────────────────────────────────

if [[ "$TIER" == "unit" || "$TIER" == "all" ]] && [ "${E2E_MODE:-}" != "1" ]; then
    echo "=== Unit tests ==="
    for script in "${TEST_DIR}/unit/test-"*.sh; do
        [ -f "$script" ] || continue
        t=$(basename "$script" .sh); t="${t#test-}"
        run "$t" "$script"
    done
    echo ""
fi

# ── Integration tests ──────────────────────────────────────────────────────────

if [[ "$TIER" == "integration" || "$TIER" == "all" ]] && [ "${E2E_MODE:-}" != "1" ]; then
    echo "=== Integration tests ==="
    for script in "${TEST_DIR}/integration/test-"*.sh; do
        [ -f "$script" ] || continue
        t=$(basename "$script" .sh); t="${t#test-}"
        run "$t" "$script"
    done
    echo ""
fi

# ── Per-service tests ──────────────────────────────────────────────────────────

if [[ "$TIER" == "all" || "$TIER" == "services" ]] || [ "${E2E_MODE:-}" = "1" ]; then
    [ "${E2E_MODE:-}" != "1" ] && echo "=== Per-service tests ==="
    while IFS= read -r script; do
        rel="${script#"${REPO}/"}"
        if [ "${E2E_MODE:-}" = "1" ]; then
            svc_path="${rel%/exist.test.sh}"
            echo ":${E2E_SERVICE_PATHS:-}:" | grep -qF ":${svc_path}:" || continue
        fi
        run "$rel" "$script"
    done < <(find "${REPO}/ai" "${REPO}/services" "${REPO}/nas" "${REPO}/hosting" \
                  -maxdepth 2 -name 'exist.test.sh' -type f 2>/dev/null | sort)
fi

# ── Results ────────────────────────────────────────────────────────────────────

echo ""
RESULT="=== Results: ${PASS} passed, ${FAIL} failed"
[ "$SKIP" -gt 0 ] && RESULT+=", ${SKIP} skipped"
RESULT+=" ==="
echo "$RESULT"

if [ "${#SKIP_NAMES[@]}" -gt 0 ]; then
    printf 'Skipped: %s\n' "$(IFS=', '; echo "${SKIP_NAMES[*]}")"
fi
if [ "${#FAIL_NAMES[@]}" -gt 0 ]; then
    echo "Failed:"
    printf '  - %s\n' "${FAIL_NAMES[@]}"
fi

[ "$FAIL" -eq 0 ]
