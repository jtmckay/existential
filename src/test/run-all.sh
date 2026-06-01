#!/usr/bin/env bash
# run-all.sh — orchestrate the existential test suite.
#
# Runs both:
#   - General-infra tests in src/test/ (syntax, gmail credentials, rclone)
#   - Every enabled service's <category>/<slug>/exist.test.sh
#
# Invoked by `./existential.sh test`. Runs inside the existential-adhoc
# container, so /repo points at the repo root and container DNS resolves on
# the `exist` network — see CLAUDE.md "Service test scripts" + Networking.

set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="${REPO_DIR:-/repo}"

PASS=0
FAIL=0
SKIP=0
FAIL_NAMES=()

run() {
    local label="$1" script="$2"
    printf '\n--- %s ---\n' "$label"
    local output rc=0
    if output=$(bash "$script" 2>&1); then
        echo "$output"
        if echo "$output" | grep -q 'skipped — '; then
            ((SKIP++))
        else
            ((PASS++))
        fi
    else
        rc=$?
        echo "$output"
        ((FAIL++))
        FAIL_NAMES+=("$label")
    fi
    return 0
}

# In E2E_MODE skip general infra tests (syntax/gmail/rclone) — those aren't
# meaningful inside the ephemeral e2e environment.
if [ "${E2E_MODE:-}" != "1" ]; then
    echo "=== General tests (src/test/) ==="
    for t in syntax existential gmail rclone; do
        [ -f "${TEST_DIR}/test-${t}.sh" ] || continue
        run "$t" "${TEST_DIR}/test-${t}.sh"
    done
fi

# Derive the EXIST_IS_* enablement var from a relative test path.
# e.g.  ai/chatterbox/exist.test.sh → EXIST_IS_AI_CHATTERBOX
path_to_var() {
    local rel="${1%/exist.test.sh}"   # ai/chatterbox
    local cat="${rel%%/*}"            # ai
    local slug="${rel#*/}"            # chatterbox
    echo "EXIST_IS_${cat^^}_${slug^^}" | tr '-' '_'
}

echo
echo "=== Per-service tests (exist.test.sh) ==="
while IFS= read -r script; do
    rel="${script#"${REPO}/"}"
    # In E2E mode only run tests for services that are actually enabled,
    # avoiding the noise of "skipped — disabled" from every other service.
    if [ "${E2E_MODE:-}" = "1" ]; then
        var=$(path_to_var "$rel")
        [ "${!var:-}" = "true" ] || continue
    fi
    run "$rel" "$script"
done < <(find "${REPO}/ai" "${REPO}/services" "${REPO}/nas" "${REPO}/hosting" \
              -maxdepth 2 -name 'exist.test.sh' -type f 2>/dev/null | sort)

echo
echo "=== Results: ${PASS} passed, ${FAIL} failed, ${SKIP} skipped ==="
if [ "${#FAIL_NAMES[@]}" -gt 0 ]; then
    echo "Failed:"
    printf '  - %s\n' "${FAIL_NAMES[@]}"
fi

[ "$FAIL" -eq 0 ]
