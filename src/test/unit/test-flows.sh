#!/usr/bin/env bash
# test-flows.sh — `./existential.sh flow`: what a flow turns on, and what off undoes.
#
#   on        its services, the flows it needs and theirs, then its files; the GPU
#             answer outranks a service it names
#   list      every flow, on ones marked
#   off       its files go, unless you changed one; services stay; a default flow
#             is remembered as off, so exist.initial.sh does not put it back
#   shipped   every shipped flow reads, and names only what exists
#
# Runs src/flows.sh against a scratch repo: the shipped flows/ and the real
# reader, a fake .env.shared. Everything is under a temp dir, removed in the trap.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
[[ -f "${REPO_DIR}/.env.exist.shared" ]] || REPO_DIR="/repo"
SRC_DIR="${REPO_DIR}/src"; [[ -f "${SRC_DIR}/flows.sh" ]] || SRC_DIR="/src"

PASS=0; FAIL=0; FAIL_NAMES=()
_ok()   { printf '  PASS  %s\n' "$1"; PASS=$((PASS + 1)); }
_fail() { printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; FAIL=$((FAIL + 1)); FAIL_NAMES+=("$1"); }
assert_eq()    { if [[ "$2" == "$3" ]]; then _ok "$1"; else _fail "$1" "expected=$2 got=$3"; fi; }
assert_has()   { if [[ "$2" == *"$3"* ]]; then _ok "$1"; else _fail "$1" "missing: $3"; fi; }
assert_lacks() { if [[ "$2" != *"$3"* ]]; then _ok "$1"; else _fail "$1" "found: $3"; fi; }
is_file() { [[ -e "$1" ]] && echo yes || echo no; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
R="${TMP}/repo"
mkdir -p "${R}/src/utils" "${R}/automation/lib"
cp -r "${REPO_DIR}/flows" "${R}/"
cp -r "${REPO_DIR}/automation/lib/file-processors.example" "${R}/automation/lib/"
cp "${SRC_DIR}/flows.sh" "${R}/src/"
cp "${SRC_DIR}/utils/flows.sh" "${SRC_DIR}/utils/gpu-vendor.sh" "${R}/src/utils/"
grep -E '^EXIST_IS_' "${REPO_DIR}/.env.exist.shared" > "${R}/.env.shared"
echo "EXIST_GPU_VENDOR=nvidia" >> "${R}/.env.shared"
D="${R}/volumes/workspace_data/.decree"

flow() { REPO_DIR="$R" bash "${R}/src/flows.sh" "$@" 2>&1 </dev/null; }
env_of() { grep "^$1=" "${R}/.env.shared" | cut -d= -f2; }

echo ""; echo "=== on ==="
out="$(flow on newsletter)"; rc=$?
assert_eq "on succeeds" "0" "$rc"
assert_eq "its cron file is in the workspace's decree project" "same" "$(cmp -s "${R}/flows/newsletter/cron/newsletter.md" "${D}/cron/newsletter.md" && echo same)"
assert_has "it says what is left for you" "$out" "feeds.txt"
assert_has "...and where to read more" "$out" "existential.company/docs/flows/newsletter"
out="$(flow on transcription)"
assert_eq "a service it names is turned on" "true" "$(env_of EXIST_IS_AI_WHISPERX)"
assert_eq "...and those of the flow it needs" "true" "$(env_of EXIST_IS_NAS_NEXTCLOUD)"
assert_eq "the needed flow's migrations are in place" "yes" "$(is_file "${D}/migrations/27-nextcloud-file-events.md")"
assert_eq "its file processor is in place" "yes" "$(is_file "${R}/automation/lib/file-processors/whisperx-transcribe.sh")"
assert_has "it says which flow came with it" "$out" "needs nextcloud-capture"
sed -i 's/^EXIST_GPU_VENDOR=.*/EXIST_GPU_VENDOR=external/' "${R}/.env.shared"
out="$(flow on local-models)"
assert_eq "the GPU answer outranks a flow's service" "false" "$(env_of EXIST_IS_AI_OLLAMA)"
assert_has "...and says so" "$out" "EXIST_IS_AI_OLLAMA stays off"
assert_eq "an unknown flow fails" "1" "$(flow on nope >/dev/null; echo $?)"

echo ""; echo "=== list ==="
out="$(flow list)"; rc=$?
assert_eq "list changes nothing (exit 3, so nothing is rebuilt)" "3" "$rc"
assert_has "an on flow is marked" "$(grep ' newsletter ' <<<"$out")" "✓"
assert_lacks "an off flow is not" "$(grep ' check-versions ' <<<"$out")" "✓"
assert_eq "without a terminal, the bare command lists" "3" "$(flow >/dev/null; echo $?)"

echo ""; echo "=== off ==="
out="$(flow off newsletter)"
assert_eq "off removes its file" "no" "$(is_file "${D}/cron/newsletter.md")"
assert_has "...and says its services stay" "$out" "stay on"
flow on newsletter >/dev/null
echo "# my change" >> "${D}/cron/newsletter.md"
out="$(flow off newsletter)"
assert_eq "an edited copy is kept" "yes" "$(is_file "${D}/cron/newsletter.md")"
assert_has "...and it says why" "$out" "you changed it"
mkdir -p "${D}/cron"; cp "${R}/flows/you-were-here/cron/you-were-here.md" "${D}/cron/"
flow off you-were-here >/dev/null
assert_eq "a default flow turned off is remembered" "you-were-here" "$(cat "${D}/flows-off" 2>/dev/null)"
assert_lacks "...so it is not a default any more" "$(REPO_DIR="$R"; . "${R}/src/utils/flows.sh"; flow_defaults)" "you-were-here"
flow on you-were-here >/dev/null
assert_eq "turning it on again forgets that" "" "$(cat "${D}/flows-off" 2>/dev/null)"

echo ""; echo "=== shipped ==="
# shellcheck source=../../utils/flows.sh
REPO_DIR="$REPO_DIR"; . "${SRC_DIR}/utils/flows.sh"
for n in $(flow_names); do
    [[ -n "$(flow_get "$n" name)" && -n "$(flow_get "$n" tagline)" ]] || _fail "${n} has a name and a tagline"
    while IFS=$'\t' read -r src _; do
        [[ -f "${REPO_DIR}/${src}" ]] || _fail "${n}: ${src} exists"
    done < <(flow_files "$n")
done
_ok "every shipped flow has a name, a tagline, and files that exist"
assert_eq "the default flows are the ones Core needs" "clean-runs health-checks look-back you-were-here" "$(flow_defaults | sort | xargs)"

# Self-check canary: TEST_SELFCHECK=1 forces one failure so this suite's own
# FAIL→exit path is proven (run-all.sh selfcheck).
[[ "${TEST_SELFCHECK:-}" == 1 ]] && _fail "selfcheck canary (deliberate failure)"

echo ""
echo "=== Results: ${PASS} passed, ${FAIL} failed ==="
if [ "$FAIL" -gt 0 ]; then echo "Failed:"; for n in "${FAIL_NAMES[@]}"; do echo "  - $n"; done; exit 1; fi
