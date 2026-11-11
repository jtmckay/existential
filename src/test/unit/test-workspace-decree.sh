#!/usr/bin/env bash
# test-workspace-decree.sh — services/automation/exist.initial.sh seeds
# workspace/.decree, the `automation` daemon's project, from the repo's
# automation/: every shipped machine and script lands once, an edit or an extra
# file is never overwritten, an older install's crons and migrations move over,
# the you-were-here digest and look-back crons are on by default, notes/my-first-note.md
# is written once, and nothing secret is written under workspace/.
#
# Runs the real script against a scratch copy of the files it reads. Read-only
# against the repo; the scratch dir is removed in the trap.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
[[ -f "${REPO_DIR}/.env.exist.shared" ]] || REPO_DIR="/repo"

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
cp -rp "${REPO_DIR}/automation/machines" "${REPO_DIR}/automation/scripts" "${REPO_DIR}/automation/plugins" "${REPO_DIR}/automation/lib" "${R}/automation/"
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

for _m in plugin plugin_share plugin_offer plugin_request notify; do
    check "the plugin system is installed: ${_m}" "[[ -f '${P}/machines/${_m}.yml' ]]"
done
for _m in note_watch reconcile develop automation_propose capture clean_runs look_back service_health you_were_here; do
    check "${_m} is on by default" "[[ -f '${P}/machines/${_m}.yml' ]]"
done
check "a plugin nothing turned on is not installed" "[[ ! -e '${P}/machines/comfy.yml' ]]"
check "scripts stay executable" "[[ -x '${P}/scripts/notify.sh' ]]"
check ".gitignore and decree-go-rest.yml (from its example) are seeded" "[[ -f '${P}/.gitignore' && -f '${P}/decree-go-rest.yml' ]]"
check "handlers.yml is seeded, watching notes" "grep -q 'machine: note_watch' '${P}/handlers.yml'"
for _d in runs/ store/ inbox/ attention/ '*.log' '.env*'; do
    check ".gitignore ignores ${_d}" "grep -qxF '${_d}' '${P}/.gitignore'"
done
check "lib/ holds the plugin system's lib" "cmp -s '${R}/automation/lib/automations/plugin.sh' '${P}/lib/automations/plugin.sh'"
check "...and the lib of plugins that are on (code-server-agents: pi, model)" "[[ -f '${P}/lib/pi.sh' && -f '${P}/lib/model.sh' ]]"
check "...and no plugin's lib that is not on" "[[ ! -e '${P}/lib/comfy' ]]"
check "an old install's cron moves over" "[[ -f '${P}/cron/old.md' && ! -e '${R}/automation/cron/old.md' ]]"
check "an old install's migration moves over" "[[ -f '${P}/migrations/01-old.md' ]]"
check "the migration ledger moves with them" "grep -qx '01-old.md' '${P}/processed.md'"
check "no secret lands under workspace/" "! grep -rqx 'secret' '${R}/volumes/workspace_data'"
check "the .env mount point is empty" "[[ -f '${P}/.env' && ! -s '${P}/.env' ]]"
check "plugins.yml, what is on, is written from its example" "cmp -s '${R}/automation/plugins.exist.yml' '${P}/plugins.yml'"
check "the you-were-here digest is on" "grep -qx 'machine: you_were_here' '${P}/cron/you-were-here.md'"
check "the weekly and monthly look backs are on" "[[ -f '${P}/cron/look-back-weekly.md' && -f '${P}/cron/look-back-monthly.md' ]]"
check "so are clean-runs and health-checks" "[[ -f '${P}/cron/clean-runs.md' && -f '${P}/cron/health-checks.md' ]]"
check "a flow that is not on is not installed" "[[ ! -e '${P}/cron/newsletter.md' ]]"
yq -i '.on -= ["health-checks"]' "${P}/plugins.yml"; run_init
check "a flow taken out of plugins.yml goes" "[[ ! -e '${P}/cron/health-checks.md' ]]"
check "...and stays out: plugins.yml is never rewritten" "! grep -q 'health-checks' '${P}/plugins.yml'"
N="${R}/volumes/workspace_data/notes/my-first-note.md"
check "notes/my-first-note.md is written" "[[ -s '${N}' ]]"
for _w in claude .decree ntfy 'matching file' .gitignore; do
    check "the first note mentions ${_w}" "grep -qiF '${_w}' '${N}'"
done
check "nothing in the workspace names Nextcloud" "! grep -rqi 'nextcloud' '${R}/volumes/workspace_data/README.md' '${N}'"

# The user's edits win, and their own files stay.
printf 'my note\n' > "${N}"
printf '# mine\n' > "${P}/machines/notify.yml"
printf 'mine\n' > "${P}/machines/mine.yml"
rm "${P}/machines/clean_runs.yml"
printf -- '---\ncron: "0 6 * * *"\nmachine: you_were_here\n---\n' > "${P}/cron/you-were-here.md"
run_init; _rc=$?
check "second run exits 0" "[[ $_rc -eq 0 ]]"
check "the plugin system follows the checkout, an edit put back" "cmp -s '${R}/automation/machines/notify.yml' '${P}/machines/notify.yml'"
check "a user's own machine is left alone" "[[ -f '${P}/machines/mine.yml' ]]"
check "a removed plugin that is on comes back" "[[ -f '${P}/machines/clean_runs.yml' ]]"
check "an edited first note is kept" "[[ \"\$(cat '${N}')\" == 'my note' ]]"
check "an edited digest schedule is kept (until the flow itself changes)" "grep -qF '0 6 * * *' '${P}/cron/you-were-here.md'"

[[ "${TEST_SELFCHECK:-}" == 1 ]] && _fail "selfcheck canary (deliberate failure)"

echo ""
echo "=== Results: ${PASS} passed, ${FAIL} failed ==="
if [ "$FAIL" -gt 0 ]; then
    printf 'Failed: %s\n' "${FAIL_NAMES[*]}"
    exit 1
fi
