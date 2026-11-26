#!/usr/bin/env bash
# test-plugins.sh — `./existential.sh plugin`: what is on is each decree project's
# own .decree/plugins/.on, and the sync installs that and all it needs.
#
#   new       a project with no list starts with the defaults tagged for it
#   on        in the list of each project it is tagged for, installed with all it
#             needs, its cron and order files
#   list      every plugin, what is on and what is on because something needs it
#   off       out of the list; it, and each need nothing on needs, removed
#   yours     a plugin file of yours stays, and gets the repo plugins it needs
#   migrate   an older install's lists (what its sync wrote) become .on, and the
#             cron files a flow installed move to the machine that runs them
#   topics    every ntfy topic used is in the Topics table, and every one there is used
#
# Runs src/plugins.sh against a scratch repo: the shipped plugins and the real
# decree. Everything is under a temp dir, removed in the trap.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
[[ -f "${REPO_DIR}/.env.exist.shared" ]] || REPO_DIR="/repo"
SRC_DIR="${REPO_DIR}/src"; [[ -f "${SRC_DIR}/plugins.sh" ]] || SRC_DIR="/src"
command -v yq >/dev/null 2>&1 || { echo "skipped — yq not available (run inside existential-adhoc)"; exit 0; }
command -v decree >/dev/null || { echo "plugins: needs decree (run it through ./existential.sh test unit)"; exit 1; }

PASS=0; FAIL=0; FAIL_NAMES=()
_ok()   { printf '  PASS  %s\n' "$1"; PASS=$((PASS + 1)); }
_fail() { printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; FAIL=$((FAIL + 1)); FAIL_NAMES+=("$1"); }
assert_eq()    { if [[ "$2" == "$3" ]]; then _ok "$1"; else _fail "$1" "expected=$2 got=$3"; fi; }
assert_has()   { if [[ "$2" == *"$3"* ]]; then _ok "$1"; else _fail "$1" "missing: $3"; fi; }
assert_lacks() { if [[ "$2" != *"$3"* ]]; then _ok "$1"; else _fail "$1" "found: $3"; fi; }
is_file() { [[ -e "$1" ]] && echo yes || echo no; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
R="${TMP}/repo"
mkdir -p "${R}/src/utils" "${R}/automation"
cp -r "${REPO_DIR}/automation/plugins" "${REPO_DIR}/automation/lib" "${R}/automation/"
cp "${REPO_DIR}/automation/decree-go-rest.exist.yml" "${R}/automation/"
cp "${SRC_DIR}/plugins.sh" "${R}/src/"
cp "${SRC_DIR}/utils/migrate.sh" "${R}/src/utils/"
D="${R}/volumes/workspace_data/.decree"
mkdir -p "$D"; cp "${REPO_DIR}/automation/decree-go-rest.exist.yml" "${D}/decree-go-rest.yml"

plug() { REPO_DIR="$R" bash "${R}/src/plugins.sh" "$@" 2>&1 </dev/null; }
on_list() { xargs < "${1:-$D}/plugins/.on"; }

echo ""; echo "=== new ==="
plug sync automation >/dev/null
assert_eq "a new project starts with the defaults" "note_watch reconcile service_health pi file_advise you_were_here" "$(on_list)"
assert_eq "...each installed" "yes" "$(is_file "${D}/machines/you_were_here/machine.yml")"
assert_eq "...with what they need (reconcile needs develop)" "yes" "$(is_file "${D}/machines/develop/machine.yml")"
assert_eq "...and their cron files (service_health's)" "yes" "$(is_file "${D}/machines/service_health/cron/health-checks.md")"
assert_eq "the plugin system's own is there too (decree_prune)" "yes" "$(is_file "${D}/machines/decree_prune/machine.yml")"
assert_has "file_advise's list names what is off" "$(cat "${D}/plugins.tsv")" "newsletter	off"

echo ""; echo "=== on ==="
out="$(plug on newsletter)"; rc=$?
assert_eq "on succeeds" "0" "$rc"
assert_has "it is in the project's list" "$(on_list)" "newsletter"
assert_has "...and says so" "$out" "newsletter is on (automation)"
assert_eq "its machine is installed" "yes" "$(is_file "${D}/machines/newsletter/machine.yml")"
assert_eq "...and its cron" "yes" "$(is_file "${D}/machines/newsletter/cron/newsletter.md")"
assert_eq "...and what it needs (model, rss)" "yes" "$( [[ -f "${D}/lib/model.sh" && -f "${D}/lib/rss.ts" ]] && echo yes || echo no)"
assert_eq "...and what is yours in its store, once" "yes" "$(is_file "${D}/store/newsletter/feeds.txt")"
plug on nextcloud_file_events >/dev/null
assert_eq "what a plugin needs comes with it (file_router)" "yes" "$(is_file "${D}/machines/file_router/machine.yml")"
assert_eq "...and its order files" "yes" "$(is_file "${D}/machines/nextcloud_file_events/order/27-nextcloud-file-events.md")"
assert_eq "...and decree_order, which runs them" "yes" "$(is_file "${D}/machines/decree_order/machine.yml")"
assert_eq "an unknown plugin fails" "1" "$(plug on nope >/dev/null; echo $?)"
plug on pull_existential >/dev/null
assert_eq "a host plugin goes in the host's list" "pull_existential" "$(on_list "${R}/.decree")"
assert_eq "...is installed there, the repo's own .decree" "yes" "$(is_file "${R}/.decree/machines/pull_existential/machine.yml")"
assert_eq "...and not in the workspace" "no" "$(is_file "${D}/machines/pull_existential/machine.yml")"
assert_eq "the host gets nothing tagged for the workspace" "no" "$(is_file "${R}/.decree/machines/notify/machine.yml")"
assert_has "a plugin for automation-backup, which is off, says so" "$(plug on triage)" "automation-backup, which is off"

echo ""; echo "=== list ==="
out="$(plug list)"; rc=$?
assert_eq "list changes nothing (exit 3)" "3" "$rc"
assert_has "a plugin you turned on is marked on" "$(grep ' newsletter ' <<<"$out")" "on"
assert_has "one on because something needs it is marked +" "$(grep ' file_router ' <<<"$out")" "+"
assert_lacks "one that is off is not" "$(grep ' check_versions ' <<<"$out" | cut -c1-6)" "on"

echo ""; echo "=== off ==="
plug off newsletter >/dev/null
assert_lacks "off takes it out of the list" "$(on_list)" "newsletter"
assert_eq "...and removes its machine and cron" "no" "$( [[ -e "${D}/machines/newsletter/machine.yml" || -e "${D}/machines/newsletter/cron/newsletter.md" ]] && echo yes || echo no)"
assert_eq "...but not what is yours" "yes" "$(is_file "${D}/store/newsletter/feeds.txt")"
plug off nextcloud_file_events >/dev/null
assert_eq "a need nothing on needs goes with it" "no" "$(is_file "${D}/machines/file_router/machine.yml")"
plug off service_health >/dev/null
assert_eq "a default goes off the same way" "no" "$(is_file "${D}/machines/service_health/machine.yml")"
assert_eq "...and stays off" "no" "$(plug sync automation >/dev/null; is_file "${D}/machines/service_health/machine.yml")"
plug on look_back >/dev/null; out="$(plug off you_were_here)"
assert_eq "one that something on needs stays (look_back needs you_were_here)" "yes" "$(is_file "${D}/machines/you_were_here/machine.yml")"
assert_has "...and says why" "$out" "something on needs it"
plug off pull_existential >/dev/null
assert_eq "a host plugin goes off in the host's project" "no" "$(is_file "${R}/.decree/machines/pull_existential/machine.yml")"

echo ""; echo "=== yours ==="
printf -- '---\nname: mine\nneeds:\n  - transcribe\nmachine:\n  description: Mine.\n  initial: a\n  states:\n    a: {final: true}\n---\n# mine\n' > "${D}/plugins/mine.md"
plug sync automation >/dev/null
assert_eq "a plugin file of yours stays" "yes" "$(is_file "${D}/plugins/mine.md")"
assert_eq "...and gets the repo plugin it needs (transcribe's lib)" "yes" "$(is_file "${D}/lib/file-processors/whisperx-transcribe.sh")"
assert_lacks "...and is not in file_advise's list of the repo's" "$(cut -f1 "${D}/plugins.tsv")" "mine"

echo ""; echo "=== migrate ==="
O="${TMP}/old"; OD="${O}/volumes/workspace_data/.decree"
mkdir -p "${O}/automation" "${OD}/plugins" "${OD}/machines/flow_you_were_here/cron" "${O}/.decree/plugins"
cp -r "${REPO_DIR}/automation/plugins" "${O}/automation/"
printf 'flow_you_were_here\nflow_clean_runs\nnotify\nskill\nyou_were_here\nflow_model\n' > "${OD}/plugins/.existential"
printf -- '---\ncron: "30 6 * * *"\nmachine: you_were_here\n---\nmine, edited\n' > "${OD}/machines/flow_you_were_here/cron/you-were-here.md"
touch "${OD}/plugins/flow_clean_runs.md" "${OD}/flows.tsv"
printf 'flow_worker\nreporting\n' > "${O}/.decree/plugins/.existential"
printf 'on:\n  - you-were-here\n' > "${O}/automation/plugins.yml"
assert_has "a sync before the migration says to run ./existential.sh" \
    "$(cd "$O/volumes/workspace_data" && bash -c 'source "$1"; plugin_sync "$2" automation' _ "${R}/automation/lib/plugin.sh" "${O}/automation/plugins" 2>&1)" "run ./existential.sh once first"
( SCRIPT_DIR="$O"; . "${R}/src/utils/migrate.sh"; _plugins_on ) >/dev/null
assert_eq "what the old sync wrote is on, a flow's lib by its plugin's name" "you_were_here model" "$(on_list "$OD")"
assert_eq "...an old name by its new one, the host's too" "report_host" "$(on_list "${O}/.decree")"
assert_eq "a flow's cron file moves to the machine it runs, edits and all" "mine, edited" "$(tail -1 "${OD}/machines/you_were_here/cron/you-were-here.md" 2>/dev/null)"
assert_eq "the old list, the flows' files and their list for file_advise go" "no" "$( [[ -e "${OD}/plugins/.existential" || -e "${OD}/plugins/flow_clean_runs.md" || -e "${OD}/flows.tsv" ]] && echo yes || echo no)"
assert_eq "plugins.yml goes to archive/" "no yes" "$(is_file "${O}/automation/plugins.yml") $(ls "${O}"/archive/plugins-*.yml >/dev/null 2>&1 && echo yes || echo no)"

echo ""; echo "=== topics ==="
# ntfy topics: the table on the ntfy docs page is the list, and every sender names one in it.
topics=" $(awk '/^### Topics/{f=1} f && /^## /{exit} f' "${REPO_DIR}/site/docs/services/ntfy.md" | sed -n 's/^| `\([a-z-]*\)`.*/\1/p' | xargs) "
used="$(cd "${REPO_DIR}" && {
    grep -rhoE 'ntfy_topic=[a-z-]+' automation | cut -d= -f2
    grep -rhoE 'ntfy_topic: (\{type: string, default: )?[a-z-]+' automation | grep -oE '[a-z-]+$'
    grep -rhoE '^x-exist-topic: [a-z-]+' automation/plugins | cut -d' ' -f2
    grep -hoE 'NTFY_URL\}/[a-z-]+\?' hosting/grafana/provisioning/alerting/*.yaml | sed 's#.*/##; s/?//'
    echo decree; } | sort -u)"   # decree: notify's default, and attention-notify's
for t in $used; do [[ "$topics" == *" ${t} "* ]] || _fail "ntfy topic ${t} is used and not in site/docs/services/ntfy.md's Topics table"; done
for t in $topics; do grep -qxF "$t" <<<"$used" || _fail "ntfy topic ${t} is in the Topics table and nothing sends to it"; done
_ok "every ntfy topic used is in the Topics table, and every one there is used"
unnamed="$(cd "${REPO_DIR}" && grep -rnE -- '--machine notify' automation | grep -v -- '--machine notify --param ntfy_topic=' | grep -v '^automation/plugins/notify.md:')"
[[ -z "$unnamed" ]] || _fail "a notify call names no topic (--machine notify --param ntfy_topic=<topic>)" "$unnamed"
_ok "every notify call names its topic"

# Self-check canary: TEST_SELFCHECK=1 forces one failure so this suite's own
# FAIL→exit path is proven (run-all.sh selfcheck).
[[ "${TEST_SELFCHECK:-}" == 1 ]] && _fail "selfcheck canary (deliberate failure)"

echo ""
echo "=== Results: ${PASS} passed, ${FAIL} failed ==="
if [ "$FAIL" -gt 0 ]; then echo "Failed:"; for n in "${FAIL_NAMES[@]}"; do echo "  - $n"; done; exit 1; fi
