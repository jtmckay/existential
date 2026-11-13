#!/usr/bin/env bash
# test-flows.sh — `./existential.sh flow`: what a flow turns on, and what off undoes.
# A flow is a plugin with no machine (automation/plugins/flows/), and the
# workspace's plugins.yml is the one record of what is on.
#
#   on        its services and those of the flows it needs, then it is in
#             plugins.yml; the sync after installs it and all it needs, its
#             crons, and its migrations after its machines; the GPU answer
#             outranks a service it names
#   list      every flow, on ones marked
#   off       out of plugins.yml, and the sync removes it; services stay
#   seed      an install from before plugins.yml keeps the flows it had on
#   shipped   every shipped flow reads, and names only what exists
#
# Runs src/flows.sh and src/lib/plugin.sh against a scratch repo: the shipped
# plugins and the real readers, a fake .env.shared. Everything is under a temp
# dir, removed in the trap.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
[[ -f "${REPO_DIR}/.env.exist.shared" ]] || REPO_DIR="/repo"
SRC_DIR="${REPO_DIR}/src"; [[ -f "${SRC_DIR}/flows.sh" ]] || SRC_DIR="/src"
command -v yq >/dev/null 2>&1 || { echo "skipped — yq not available (run inside existential-adhoc)"; exit 0; }

PASS=0; FAIL=0; FAIL_NAMES=()
_ok()   { printf '  PASS  %s\n' "$1"; PASS=$((PASS + 1)); }
_fail() { printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; FAIL=$((FAIL + 1)); FAIL_NAMES+=("$1"); }
assert_eq()    { if [[ "$2" == "$3" ]]; then _ok "$1"; else _fail "$1" "expected=$2 got=$3"; fi; }
assert_has()   { if [[ "$2" == *"$3"* ]]; then _ok "$1"; else _fail "$1" "missing: $3"; fi; }
assert_lacks() { if [[ "$2" != *"$3"* ]]; then _ok "$1"; else _fail "$1" "found: $3"; fi; }
is_file() { [[ -e "$1" ]] && echo yes || echo no; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
R="${TMP}/repo"
mkdir -p "${R}/src/utils" "${R}/src/lib" "${R}/automation"
cp -r "${REPO_DIR}/automation/machines" "${REPO_DIR}/automation/scripts" "${REPO_DIR}/automation/plugins" "${REPO_DIR}/automation/lib" "${R}/automation/"
cp "${REPO_DIR}/automation/plugins.exist.yml" "${REPO_DIR}/automation/plugins.host.exist.yml" "${R}/automation/"
cp "${SRC_DIR}/lib/plugin.sh" "${R}/src/lib/"
cp "${SRC_DIR}/flows.sh" "${R}/src/"
cp "${SRC_DIR}/utils/flows.sh" "${SRC_DIR}/utils/gpu-vendor.sh" "${R}/src/utils/"
grep -E '^EXIST_IS_' "${REPO_DIR}/.env.exist.shared" > "${R}/.env.shared"
echo "EXIST_GPU_VENDOR=nvidia" >> "${R}/.env.shared"
D="${R}/volumes/workspace_data/.decree"
mkdir -p "$D"; cp "${REPO_DIR}/automation/decree-go-rest.exist.yml" "${D}/decree-go-rest.yml"
# decree check is the gate's (test decree); here it always passes.
mkdir -p "${TMP}/bin"; printf '#!/bin/sh\nexit 0\n' > "${TMP}/bin/decree"; chmod +x "${TMP}/bin/decree"

flow() { REPO_DIR="$R" bash "${R}/src/flows.sh" "$@" 2>&1 </dev/null; }
sync() { PATH="${TMP}/bin:${PATH}" REPO_DIR="$R" bash "${R}/src/lib/plugin.sh" sync automation >/dev/null 2>&1; }
env_of() { grep "^$1=" "${R}/.env.shared" | cut -d= -f2; }
on_list() { yq -r '.on[]' "${D}/plugins.yml" | xargs; }

echo ""; echo "=== on ==="
out="$(flow on weekly-newsletter)"; rc=$?
assert_eq "on succeeds" "0" "$rc"
assert_has "it is in plugins.yml, with the flows every install starts with" "$(on_list)" "weekly-newsletter note-to-automation"
assert_has "it says what is left for you" "$out" "feeds.txt"
assert_has "...and where to read more" "$out" "existential.company/docs/flows/newsletter"
sync
assert_eq "the sync installs its machine" "yes" "$(is_file "${D}/machines/newsletter.yml")"
assert_eq "...and its cron" "yes" "$(is_file "${D}/cron/newsletter.md")"
assert_eq "...and what that needs (model, rss)" "yes" "$( [[ -f "${D}/lib/model.sh" && -f "${D}/lib/rss.ts" ]] && echo yes || echo no)"
assert_eq "...and yours from its example, once" "yes" "$(is_file "${D}/lib/newsletter/feeds.txt")"
out="$(flow on transcription)"
assert_eq "with no answer, no service is turned on" "false false" "$(env_of EXIST_IS_AI_WHISPERX) $(env_of EXIST_IS_NAS_NEXTCLOUD)"
assert_has "...the flow is on, and it says what is still off" "$out" "service on nextcloud automation-webhook whisperx"
out="$(printf "y\nn\n" | REPO_DIR="$R" bash "${R}/src/flows.sh" on transcription 2>&1)"; sync
assert_eq "each service is asked for: yes turns that one on" "true" "$(env_of EXIST_IS_NAS_NEXTCLOUD)"
assert_eq "...and no leaves the next one off" "false" "$(env_of EXIST_IS_AI_WHISPERX)"
assert_has "it asks by name" "$out" "uses whisperx, which is off"
assert_has "it says which flow came with it" "$out" "needs nextcloud-capture"
assert_eq "the needed flow's migrations are queued" "yes" "$(is_file "${D}/migrations/27-nextcloud-file-events.md")"
assert_eq "...after the machine they run" "yes" "$(is_file "${D}/machines/nextcloud_file_events.yml")"
assert_eq "its file processor, the transcribe plugin, is installed" "yes" "$(is_file "${D}/lib/file-processors/whisperx-transcribe.sh")"
sed -i 's/^EXIST_GPU_VENDOR=.*/EXIST_GPU_VENDOR=external/' "${R}/.env.shared"
out="$(flow on local-models)"
assert_eq "the GPU answer outranks a flow's service" "false" "$(env_of EXIST_IS_AI_OLLAMA)"
assert_has "...and says so" "$out" "EXIST_IS_AI_OLLAMA stays off"
assert_eq "an unknown flow fails" "1" "$(flow on nope >/dev/null; echo $?)"
assert_eq "a library is not a flow you turn on" "1" "$(flow on model >/dev/null; echo $?)"
flow on auto-update >/dev/null
assert_eq "a host flow goes in the host's plugins.yml" "auto-update" "$(sed -n 's/^  - //p' "${R}/host/.decree/plugins.yml")"
assert_lacks "...not the workspace's" "$(on_list)" "auto-update"
assert_has "...and the list shows it on" "$(flow list | grep ' auto-update ')" "✓"
flow off auto-update >/dev/null
assert_eq "...and off takes it out" "" "$(sed -n 's/^  - //p' "${R}/host/.decree/plugins.yml")"

echo ""; echo "=== list ==="
out="$(flow list)"; rc=$?
assert_eq "list changes nothing (exit 3, so nothing is rebuilt)" "3" "$rc"
assert_has "an on flow is marked" "$(grep ' weekly-newsletter ' <<<"$out")" "✓"
assert_lacks "an off flow is not" "$(grep ' check-versions ' <<<"$out")" "✓"
assert_lacks "a library is not listed" "$(awk '{ print ($1 == "✓" ? $2 : $1) }' <<<"$out" | xargs)" " model "
assert_eq "without a terminal, the bare command lists" "3" "$(flow >/dev/null; echo $?)"

echo ""; echo "=== off ==="
out="$(flow off weekly-newsletter)"
assert_lacks "off takes it out of plugins.yml" "$(on_list)" "weekly-newsletter"
assert_has "...and says its services stay" "$out" "stay on"
sync
assert_eq "the sync removes its machine and cron" "no" "$( [[ -e "${D}/machines/newsletter.yml" || -e "${D}/cron/newsletter.md" ]] && echo yes || echo no)"
assert_eq "...but not what is yours" "yes" "$(is_file "${D}/lib/newsletter/feeds.txt")"
flow off health-checks >/dev/null; sync
assert_eq "a flow every install starts with goes off the same way" "no" "$(is_file "${D}/cron/health-checks.md")"
assert_eq "...and stays off" "no" "$(sync; is_file "${D}/cron/health-checks.md")"
flow off you-were-here >/dev/null; sync
assert_eq "one another flow that is on needs stays (look-back needs you-were-here)" "yes" "$(is_file "${D}/cron/you-were-here.md")"

echo ""; echo "=== seed ==="
# An install from before plugins.yml: an old flow's cron in place, a default flow it turned off.
O="${TMP}/old"; mkdir -p "$O"; cp -r "${R}/automation" "${R}/src" "$O/"
mkdir -p "${O}/volumes/workspace_data/.decree/cron"
printf -- '---\nmachine: newsletter\ncron: "0 7 * * 1"\n---\n' > "${O}/volumes/workspace_data/.decree/cron/newsletter.md"
echo look-back > "${O}/volumes/workspace_data/.decree/flows-off"
PATH="${TMP}/bin:${PATH}" REPO_DIR="$O" bash "${O}/src/lib/plugin.sh" seed automation >/dev/null 2>&1
seeded="$(yq -r '.on[]' "${O}/volumes/workspace_data/.decree/plugins.yml" | xargs)"
assert_has "a flow it had on stays on" "$seeded" "weekly-newsletter"
assert_lacks "a default it had turned off stays off" "$seeded" "look-back"
assert_has "...and the other defaults are on" "$seeded" "you-were-here"
assert_eq "flows-off is gone: plugins.yml says it all" "no" "$(is_file "${O}/volumes/workspace_data/.decree/flows-off")"

echo ""; echo "=== shipped ==="
# shellcheck source=../../utils/flows.sh
REPO_DIR="$REPO_DIR"; . "${SRC_DIR}/utils/flows.sh"
for n in $(flow_names); do
    [[ -n "$(flow_get "$n" name)" && -n "$(flow_get "$n" docs)" ]] || _fail "${n} has a name and docs"
done
_ok "every shipped flow has a name, a tagline and docs"
for n in $(flow_defaults); do flow_exists "$n" || _fail "plugins.exist.yml turns on ${n}, which is no flow"; done
_ok "every flow plugins.exist.yml turns on is one"

# Self-check canary: TEST_SELFCHECK=1 forces one failure so this suite's own
# FAIL→exit path is proven (run-all.sh selfcheck).
[[ "${TEST_SELFCHECK:-}" == 1 ]] && _fail "selfcheck canary (deliberate failure)"

echo ""
echo "=== Results: ${PASS} passed, ${FAIL} failed ==="
if [ "$FAIL" -gt 0 ]; then echo "Failed:"; for n in "${FAIL_NAMES[@]}"; do echo "  - $n"; done; exit 1; fi
