#!/usr/bin/env bash
# test-service-flags.sh — `./existential.sh service`: one service's flag, on and off.
#
# Runs src/services.sh against a scratch repo: the real category folders (empty),
# the real helpers, a fake .env.shared. Everything is under a temp dir, removed in the trap.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
[[ -f "${REPO_DIR}/.env.exist.shared" ]] || REPO_DIR="/repo"
SRC_DIR="${REPO_DIR}/src"; [[ -f "${SRC_DIR}/services.sh" ]] || SRC_DIR="/src"

PASS=0; FAIL=0; FAIL_NAMES=()
_ok()   { printf '  PASS  %s\n' "$1"; PASS=$((PASS + 1)); }
_fail() { printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; FAIL=$((FAIL + 1)); FAIL_NAMES+=("$1"); }
assert_eq()    { if [[ "$2" == "$3" ]]; then _ok "$1"; else _fail "$1" "expected=$2 got=$3"; fi; }
assert_has()   { if [[ "$2" == *"$3"* ]]; then _ok "$1"; else _fail "$1" "missing: $3"; fi; }
assert_lacks() { if [[ "$2" != *"$3"* ]]; then _ok "$1"; else _fail "$1" "found: $3"; fi; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
R="${TMP}/repo"
mkdir -p "${R}/src/utils" "${R}/ai/ollama" "${R}/services/it-tools" "${R}/services/ntfy"
cp "${SRC_DIR}/services.sh" "${R}/src/"
cp "${SRC_DIR}/utils/service-common.sh" "${SRC_DIR}/utils/gpu-vendor.sh" "${R}/src/utils/"
grep -E '^EXIST_IS_' "${REPO_DIR}/.env.exist.shared" > "${R}/.env.shared"
echo "EXIST_GPU_VENDOR=nvidia" >> "${R}/.env.shared"

svc() { REPO_DIR="$R" bash "${R}/src/services.sh" "$@" 2>&1 </dev/null; }
env_of() { grep "^$1=" "${R}/.env.shared" | cut -d= -f2; }

echo ""; echo "=== on / off ==="
svc on it-tools >/dev/null
assert_eq "on sets its flag, by slug" "true" "$(env_of EXIST_IS_SERVICES_IT_TOOLS)"
out="$(svc off services/ntfy)"
assert_eq "off clears it, by category/slug" "false" "$(env_of EXIST_IS_SERVICES_NTFY)"
assert_has "...and says how its containers stop" "$out" "--remove-orphans"
sed -i 's/^EXIST_GPU_VENDOR=.*/EXIST_GPU_VENDOR=external/' "${R}/.env.shared"
out="$(svc on ollama)"
assert_eq "the GPU answer outranks it" "false" "$(env_of EXIST_IS_AI_OLLAMA)"
assert_has "...and says so" "$out" "stays off"
assert_eq "an unknown service fails" "1" "$(svc on nope >/dev/null; echo $?)"

echo ""; echo "=== list ==="
out="$(svc list)"; rc=$?
assert_eq "list changes nothing (exit 3, so nothing is rebuilt)" "3" "$rc"
assert_has "an on service is marked" "$(grep 'services/it-tools' <<<"$out")" "✓"
assert_lacks "an off one is not" "$(grep 'services/ntfy' <<<"$out")" "✓"
assert_eq "without a terminal, the bare command lists" "3" "$(svc >/dev/null; echo $?)"

# Self-check canary: TEST_SELFCHECK=1 forces one failure so this suite's own
# FAIL→exit path is proven (run-all.sh selfcheck).
[[ "${TEST_SELFCHECK:-}" == 1 ]] && _fail "selfcheck canary (deliberate failure)"

echo ""
echo "=== Results: ${PASS} passed, ${FAIL} failed ==="
if [ "$FAIL" -gt 0 ]; then echo "Failed:"; for n in "${FAIL_NAMES[@]}"; do echo "  - $n"; done; exit 1; fi
