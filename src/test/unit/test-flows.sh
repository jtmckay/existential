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
cp -r "${REPO_DIR}/automation/plugins" "${REPO_DIR}/automation/lib" "${R}/automation/"
cp "${REPO_DIR}/automation/plugins.exist.yml" "${R}/automation/"
cp "${SRC_DIR}/lib/plugin.sh" "${R}/src/lib/"
cp "${SRC_DIR}/flows.sh" "${R}/src/"
cp "${SRC_DIR}/utils/flows.sh" "${SRC_DIR}/utils/gpu-vendor.sh" "${R}/src/utils/"
grep -E '^EXIST_IS_' "${REPO_DIR}/.env.exist.shared" > "${R}/.env.shared"
echo "EXIST_GPU_VENDOR=nvidia" >> "${R}/.env.shared"
D="${R}/volumes/workspace_data/.decree"
mkdir -p "$D"; cp "${REPO_DIR}/automation/decree-go-rest.exist.yml" "${D}/decree-go-rest.yml"
# The real decree, which installs what the sync writes (the adhoc image has it).
command -v decree >/dev/null || { echo "flows: needs decree (run it through ./existential.sh test unit)"; exit 1; }
mkdir -p "${TMP}/bin"

flow() { REPO_DIR="$R" bash "${R}/src/flows.sh" "$@" 2>&1 </dev/null; }
sync() { PATH="${TMP}/bin:${PATH}" REPO_DIR="$R" bash "${R}/src/lib/plugin.sh" sync automation >/dev/null 2>&1; }
env_of() { grep "^$1=" "${R}/.env.shared" | cut -d= -f2; }
on_list() { yq -r '.on[]' "${R}/automation/plugins.yml" | xargs; }

echo ""; echo "=== on ==="
out="$(flow on weekly-newsletter)"; rc=$?
assert_eq "on succeeds" "0" "$rc"
assert_has "it is in plugins.yml, with the flows every install starts with" "$(on_list)" "weekly-newsletter note-to-automation"
assert_has "it says what is left for you" "$out" "feeds.txt"
assert_has "...and where to read more" "$out" "existential.company/docs/flows/newsletter"
sync
assert_eq "the sync installs its machine" "yes" "$(is_file "${D}/machines/newsletter/machine.yml")"
assert_eq "...and its cron" "yes" "$(is_file "${D}/machines/flow_weekly_newsletter/cron/newsletter.md")"
assert_eq "...and what that needs (model, rss)" "yes" "$( [[ -f "${D}/lib/model.sh" && -f "${D}/lib/rss.ts" ]] && echo yes || echo no)"
assert_eq "...and what is yours in its store, once" "yes" "$(is_file "${D}/store/newsletter/feeds.txt")"
out="$(flow on transcription)"
assert_eq "with no answer, no service is turned on" "false false" "$(env_of EXIST_IS_AI_WHISPERX) $(env_of EXIST_IS_NAS_NEXTCLOUD)"
assert_has "...the flow is on, and it says what is still off" "$out" "service on nextcloud automation-webhook whisperx"
out="$(printf "y\nn\n" | REPO_DIR="$R" bash "${R}/src/flows.sh" on transcription 2>&1)"; sync
assert_eq "each service is asked for: yes turns that one on" "true" "$(env_of EXIST_IS_NAS_NEXTCLOUD)"
assert_eq "...and no leaves the next one off" "false" "$(env_of EXIST_IS_AI_WHISPERX)"
assert_has "it asks by name" "$out" "uses whisperx, which is off"
assert_has "it says which flow came with it" "$out" "needs nextcloud-capture"
assert_eq "the needed flow's order files are in" "yes" "$(is_file "${D}/machines/flow_nextcloud_capture/order/27-nextcloud-file-events.md")"
assert_eq "...after the machine they run" "yes" "$(is_file "${D}/machines/nextcloud_file_events/machine.yml")"
assert_eq "its file processor, the transcribe plugin, is installed" "yes" "$(is_file "${D}/lib/file-processors/whisperx-transcribe.sh")"
sed -i 's/^EXIST_GPU_VENDOR=.*/EXIST_GPU_VENDOR=external/' "${R}/.env.shared"
out="$(flow on local-models)"
assert_eq "the GPU answer outranks a flow's service" "false" "$(env_of EXIST_IS_AI_OLLAMA)"
assert_has "...and says so" "$out" "EXIST_IS_AI_OLLAMA stays off"
assert_eq "an unknown flow fails" "1" "$(flow on nope >/dev/null; echo $?)"
assert_eq "a library is not a flow you turn on" "1" "$(flow on model >/dev/null; echo $?)"
flow on auto-update >/dev/null
assert_has "a host flow goes in the same list" "$(on_list)" "auto-update"
sync
assert_eq "...and its x-exist-project keeps it out of the workspace" "no" "$(is_file "${D}/machines/update/machine.yml")"
PATH="${TMP}/bin:${PATH}" REPO_DIR="$R" bash "${R}/src/lib/plugin.sh" sync host >/dev/null 2>&1
assert_eq "...and in the host's project, the repo's own .decree" "yes" "$(is_file "${R}/.decree/machines/update/machine.yml")"
assert_eq "...which gets nothing tagged for the workspace" "no" "$(is_file "${R}/.decree/machines/notify/machine.yml")"
assert_has "...and the list shows it on" "$(flow list | grep ' auto-update ')" "✓"
flow off auto-update >/dev/null
assert_lacks "...and off takes it out" "$(on_list)" "auto-update"

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
assert_eq "the sync removes its machine and cron" "no" "$( [[ -e "${D}/machines/newsletter/machine.yml" || -e "${D}/machines/flow_weekly_newsletter/cron/newsletter.md" ]] && echo yes || echo no)"
assert_eq "...but not what is yours" "yes" "$(is_file "${D}/store/newsletter/feeds.txt")"
flow off health-checks >/dev/null; sync
assert_eq "a flow every install starts with goes off the same way" "no" "$(is_file "${D}/machines/flow_health_checks/cron/health-checks.md")"
assert_eq "...and stays off" "no" "$(sync; is_file "${D}/machines/flow_health_checks/cron/health-checks.md")"
flow on look-back >/dev/null; flow on you-were-here >/dev/null; flow off you-were-here >/dev/null; sync
assert_eq "one another flow that is on needs stays (look-back needs you-were-here)" "yes" "$(is_file "${D}/machines/flow_you_were_here/cron/you-were-here.md")"

echo ""; echo "=== seed ==="
# An install from before plugins.yml: an old flow's cron in place, a default flow it turned off.
O="${TMP}/old"; mkdir -p "$O"; cp -r "${R}/automation" "${R}/src" "$O/"
mkdir -p "${O}/volumes/workspace_data/.decree/cron"
printf -- '---\nmachine: newsletter\ncron: "0 7 * * 1"\n---\n' > "${O}/volumes/workspace_data/.decree/cron/newsletter.md"
echo health-checks > "${O}/volumes/workspace_data/.decree/flows-off"
rm -f "${O}/automation/plugins.yml"
PATH="${TMP}/bin:${PATH}" REPO_DIR="$O" bash "${O}/src/lib/plugin.sh" seed >/dev/null 2>&1
seeded="$(yq -r '.on[]' "${O}/automation/plugins.yml" | xargs)"
assert_has "a flow it had on stays on" "$seeded" "weekly-newsletter"
assert_lacks "a default it had turned off stays off" "$seeded" "health-checks"
assert_has "...and the other defaults are on" "$seeded" "note-to-automation"
assert_eq "flows-off is gone: plugins.yml says it all" "no" "$(is_file "${O}/volumes/workspace_data/.decree/flows-off")"

# An install from when each project had its own list: each is folded in, once.
O="${TMP}/three"; mkdir -p "$O"; cp -r "${R}/automation" "${R}/src" "$O/"; rm -f "${O}/automation/plugins.yml"
mkdir -p "${O}/volumes/workspace_data/.decree" "${O}/host/.decree" "${O}/services/automation-backup"
printf 'on:\n  - look-back\n' > "${O}/volumes/workspace_data/.decree/plugins.yml"
printf 'on:\n  - worker\n' > "${O}/host/.decree/plugins.yml"
printf 'on:\n  - triage\n' > "${O}/services/automation-backup/plugins.yml"
REPO_DIR="$O" bash "${O}/src/lib/plugin.sh" seed >/dev/null 2>&1
seeded=" $(yq -r '.on[]' "${O}/automation/plugins.yml" | xargs) "
assert_has "the workspace's list is kept" "$seeded" " look-back "
assert_lacks "...in place of the defaults for it" "$seeded" " health-checks "
assert_has "the host's list is kept" "$seeded" " worker "
assert_has "automation-backup's list is kept" "$seeded" " triage "
assert_lacks "...in place of the defaults for it" "$seeded" " db_backup "
assert_eq "the three old lists are gone" "no" "$( [[ -e "${O}/volumes/workspace_data/.decree/plugins.yml" || -e "${O}/host/.decree/plugins.yml" || -e "${O}/services/automation-backup/plugins.yml" ]] && echo yes || echo no)"

echo ""; echo "=== shipped ==="
# shellcheck source=../../utils/flows.sh
REPO_DIR="$REPO_DIR"; . "${SRC_DIR}/utils/flows.sh"
for n in $(flow_names); do
    [[ -n "$(flow_get "$n" name)" && -n "$(flow_get "$n" docs)" ]] || _fail "${n} has a name and docs"
done
_ok "every shipped flow has a name, a tagline and docs"
for n in $(flow_defaults); do plugin_file "$n" >/dev/null || _fail "plugins.exist.yml turns on ${n}, which is no plugin"; done
_ok "everything plugins.exist.yml turns on is a plugin"
for n in $(flow_defaults); do [[ "$n" == clean-runs || "$n" == clean_runs ]] || ! plugin_in host "$n" || _fail "plugins.exist.yml turns on ${n} for the host: only clean-runs runs there until you say so"; done
_ok "plugins.exist.yml turns on clean-runs alone for the host"
assert_eq "the default flows are note-to-automation, clean-runs and health-checks" "clean-runs health-checks note-to-automation" "$(flow_defaults | while read -r n; do flow_exists "$n" && echo "$n"; done | sort | xargs)"

# Self-check canary: TEST_SELFCHECK=1 forces one failure so this suite's own
# FAIL→exit path is proven (run-all.sh selfcheck).
[[ "${TEST_SELFCHECK:-}" == 1 ]] && _fail "selfcheck canary (deliberate failure)"

echo ""
echo "=== Results: ${PASS} passed, ${FAIL} failed ==="
if [ "$FAIL" -gt 0 ]; then echo "Failed:"; for n in "${FAIL_NAMES[@]}"; do echo "  - $n"; done; exit 1; fi
