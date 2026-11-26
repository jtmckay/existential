#!/usr/bin/env bash
# test-workspace-decree.sh — services/automation/exist.initial.sh seeds
# workspace/.decree, the `automation` daemon's project, from the repo's
# automation/: the plugins that are on are written to plugins/ and decree
# installs them, a person's own files stay, an older install's crons and migrations move over,
# only note-to-automation, clean-runs and health-checks are on by default, notes/my-first-note.md
# is written once, and nothing secret is written under workspace/.
#
# Runs the real script, and the real decree, against a scratch copy of the files
# it reads. Read-only against the repo; the scratch dir is removed in the trap.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
[[ -f "${REPO_DIR}/.env.exist.shared" ]] || REPO_DIR="/repo"
command -v decree >/dev/null || { echo "workspace-decree: needs decree (run it through ./existential.sh test unit)"; exit 1; }

PASS=0; FAIL=0; FAIL_NAMES=()
_ok()   { printf '  PASS  %s\n' "$1"; PASS=$((PASS + 1)); }
_fail() { printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; FAIL=$((FAIL + 1)); FAIL_NAMES+=("$1"); }
check() { if eval "$2"; then _ok "$1"; else _fail "$1" "$2"; fi; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
R="${TMP}/repo"
P="${R}/volumes/workspace_data/.decree"

mkdir -p "${R}/services/automation" "${R}/automation"
cp "${REPO_DIR}/services/automation/exist.initial.sh" "${R}/services/automation/"
cp -rp "${REPO_DIR}/automation/plugins" "${REPO_DIR}/automation/lib" "${R}/automation/"
cp -p "${REPO_DIR}/automation/.gitignore" "${REPO_DIR}/automation/decree-go-rest.exist.yml" "${REPO_DIR}/automation/handlers.exist.yml" "${R}/automation/"
mkdir -p "${R}/src/utils" "${R}/src/lib"
cp "${REPO_DIR}/src/lib/plugin.sh" "${R}/src/lib/"
grep -E "^EXIST_IS_" "${REPO_DIR}/.env.exist.shared" > "${R}/.env.shared"
cp "${REPO_DIR}/automation/plugins.exist.yml" "${R}/automation/"
cp "${REPO_DIR}/src/utils/flows.sh" "${R}/src/utils/"
# An install from before workspace/.decree: an active cron, a migration and its ledger.
mkdir -p "${R}/automation/cron" "${R}/automation/migrations" "${R}/automation/secrets/rclone"
printf -- '---\ncron: "* * * * *"\nmachine: notify\n---\n' > "${R}/automation/cron/old.md"
printf -- '---\nmachine: notify\n---\n' > "${R}/automation/migrations/01-old.md"
printf '01-old.md\n' > "${R}/automation/processed.md"
printf 'secret\n' > "${R}/automation/secrets/rclone/rclone.conf"

# In adhoc, as on a real install: the plugin sync needs yq.
run_init() { IN_CONTAINER=1 bash "${R}/services/automation/exist.initial.sh" >/dev/null 2>&1; }

run_init; _rc=$?
check "first run exits 0" "[[ $_rc -eq 0 ]]"

check "notify, which every machine tells you through, is installed" "[[ -f '${P}/machines/notify/machine.yml' ]]"
check "nothing here installs a plugin: there is no plugin machine" "[[ ! -e '${P}/machines/plugin/machine.yml' ]]"
check "sharing plugins with another stack is off until asked for" "[[ ! -e '${P}/machines/plugin_share/machine.yml' ]] && ! grep -q 'plugin_share' '${P}/decree-go-rest.yml'"
for _m in note_watch reconcile develop automation_propose decree_prune service_health skill; do
    check "${_m} is on by default" "[[ -f '${P}/machines/${_m}/machine.yml' ]]"
done
check "a plugin nothing turned on is not installed" "[[ ! -e '${P}/machines/comfy/machine.yml' ]]"
check "scripts stay executable" "[[ -x '${P}/machines/notify/scripts/notify.sh' ]]"
check ".gitignore and decree-go-rest.yml (from its example) are seeded" "[[ -f '${P}/.gitignore' && -f '${P}/decree-go-rest.yml' ]]"
check "handlers.yml is seeded, watching notes" "grep -q 'machine: note_watch' '${P}/handlers.yml'"
for _d in runs/ store/ inbox/ attention/ '*.log' '.env*'; do
    check ".gitignore ignores ${_d}" "grep -qxF '${_d}' '${P}/.gitignore'"
done
check "lib/ holds the plugin system's lib" "cmp -s '${R}/automation/lib/plugin.sh' '${P}/lib/plugin.sh'"
check "...and the lib of plugins that are on (note-to-automation: model)" "[[ -f '${P}/lib/model.sh' ]]"
check "...and no plugin's lib that is not on" "[[ ! -e '${P}/lib/comfy' ]]"
check "an old install's cron moves over" "[[ -f '${P}/cron/old.md' && ! -e '${R}/automation/cron/old.md' ]]"
check "an old install's migration and its ledger move over, then to the archive (decree 0.6 has none)" "[[ -f '${P}/archive/0.5/migrations/01-old.md' && -f '${P}/archive/0.5/processed.md' ]]"
check "no secret lands under workspace/" "! grep -rqx 'secret' '${R}/volumes/workspace_data'"
check "the .env mount point is empty" "[[ -f '${P}/.env' && ! -s '${P}/.env' ]]"
check "plugins.yml, what is on, is written from its example" "cmp -s '${R}/automation/plugins.exist.yml' '${R}/automation/plugins.yml'"
check "...beside the plugins, not in the workspace the automation daemon can write" "[[ ! -e '${P}/plugins.yml' ]]"
check "nothing tagged for another project is installed (x-exist-project: backup, host)" "[[ ! -e '${P}/machines/triage/machine.yml' && ! -e '${P}/machines/pull_existential/machine.yml' ]]"
check "plugins.exist.yml turns on three flows and nothing else" "[[ \"\$(yq -r '.on | join(\" \")' '${R}/automation/plugins.exist.yml')\" == 'note-to-automation clean-runs health-checks' ]]"
check "the digest, the look backs, capture and the agents are off until asked for" "[[ ! -e '${P}/machines/flow_you_were_here' && ! -e '${P}/machines/flow_look_back' && ! -e '${P}/machines/capture/machine.yml' && ! -e '${P}/lib/pi.sh' ]]"
check "clean-runs (decree's decree_prune) and health-checks are on" "[[ -f '${P}/machines/decree_prune/cron/weekly.md' && -f '${P}/machines/flow_health_checks/cron/health-checks.md' ]]"
check "a flow that is not on is not installed" "[[ ! -e '${P}/machines/flow_weekly_newsletter' ]]"
yq -i '.on -= ["health-checks"]' "${R}/automation/plugins.yml"; run_init
check "a flow taken out of plugins.yml goes" "[[ ! -e '${P}/machines/flow_health_checks/cron/health-checks.md' ]]"
check "...and stays out: plugins.yml is never rewritten" "! grep -q 'health-checks' '${R}/automation/plugins.yml'"
N="${R}/volumes/workspace_data/notes/my-first-note.md"
check "notes/my-first-note.md is written" "[[ -s '${N}' ]]"
for _w in claude .decree ntfy 'matching file' .gitignore; do
    check "the first note mentions ${_w}" "grep -qiF '${_w}' '${N}'"
done
check "nothing in the workspace names Nextcloud" "! grep -rqi 'nextcloud' '${R}/volumes/workspace_data/README.md' '${N}'"

# The user's edits win, and their own files stay.
printf 'my note\n' > "${N}"
rm "${P}/machines/notify/machine.yml"
mkdir -p "${P}/machines/mine"; printf 'mine\n' > "${P}/machines/mine/machine.yml"
rm "${P}/machines/decree_prune/machine.yml"
chmod -R u+w "${P}/machines/decree_prune/cron"; printf -- '---\ncron: "0 6 * * *"\nmachine: decree_prune\n---\n' > "${P}/machines/decree_prune/cron/weekly.md"
run_init; _rc=$?
check "second run exits 0" "[[ $_rc -eq 0 ]]"
check "the plugin system is always installed: a removed notify comes back" "grep -q '^name: notify' '${P}/machines/notify/machine.yml'"
check "a user's own machine is left alone" "[[ -f '${P}/machines/mine/machine.yml' ]]"
check "a removed plugin that is on comes back" "[[ -f '${P}/machines/decree_prune/machine.yml' ]]"
check "an edited first note is kept" "[[ \"\$(cat '${N}')\" == 'my note' ]]"
check "an edited schedule is kept (decree installs a plugin's cron files once)" "grep -qF '0 6 * * *' '${P}/machines/decree_prune/cron/weekly.md'"

check "skill writes decree's skill to the workspace root, not this project's" "grep -qxF '/workspace/.claude/skills/decree' '${P}/machines/skill/scripts/dirs'"

# gpu_lease is decree's decree_lease with this stack's rules and swap, which run from
# the installed copy with its scripts read-only (decree installs code that way); a
# client's release reaches a gpu_lease run and nothing else.
G="${TMP}/gl"; mkdir -p "${G}"
( cd "${G}" && git init -q && source "${REPO_DIR}/automation/lib/plugin.sh" && plugin_unpack gpu_lease "${G}" ) >/dev/null 2>&1
check "gpu_lease installs on decree_lease, with gpu_release" "[[ -f '${G}/.decree/machines/decree_lease/machine.yml' && -x '${G}/.decree/machines/gpu_lease/scripts/swap/gpu.sh' && -f '${G}/.decree/machines/gpu_release/machine.yml' ]]"
chmod -R a-w "${G}/.decree/machines/gpu_lease/scripts" "${G}/.decree/machines/decree_lease/scripts"
_id="$(cd "${G}" && echo | decree emit --machine gpu_lease --param resource=gpu --param mode=llm --param holder=box)"
( cd "${G}" && timeout 120 decree daemon --once >"${TMP}/gl.log" 2>&1 ) & _pid=$!
_st() { jq -r '.state // ""' "${G}/.decree/machines/gpu_lease/state/status/leases/${_id}.json" 2>/dev/null; }
for _i in $(seq 60); do [[ "$(_st)" == held ]] && break; sleep 1; done
check "a lease is held, its swap run from the read-only copy" "[[ '$(_st)' == held ]] && ls '${G}'/.decree/runs/${_id}/*-swap.log >/dev/null 2>&1"
( cd "${G}" && echo | decree emit --machine gpu_release --param lease=nope >/dev/null
  echo | decree emit --machine gpu_release --param lease="${_id}" >/dev/null )
wait "${_pid}"
check "...and released by gpu_release" "[[ '$(_st)' == released ]]"
check "...which answers nothing that is not a gpu_lease run" "grep -q 'nope is no GPU lease' '${TMP}/gl.log'"
chmod -R u+w "${G}"

[[ "${TEST_SELFCHECK:-}" == 1 ]] && _fail "selfcheck canary (deliberate failure)"

echo ""
echo "=== Results: ${PASS} passed, ${FAIL} failed ==="
if [ "$FAIL" -gt 0 ]; then
    printf 'Failed: %s\n' "${FAIL_NAMES[*]}"
    exit 1
fi
