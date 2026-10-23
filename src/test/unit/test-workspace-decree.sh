#!/usr/bin/env bash
# test-workspace-decree.sh — services/automation/exist.initial.sh seeds
# workspace/.decree, the `automation` daemon's project, from the repo's
# automation/: every shipped machine and script lands once, an edit or an extra
# file is never overwritten, an older install's crons and migrations move over,
# the you-were-here digest cron is on by default, and nothing secret is written
# under workspace/.
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

mkdir -p "${R}/services/automation/backup" "${R}/automation"
cp "${REPO_DIR}/services/automation/exist.initial.sh" "${R}/services/automation/"
cp -r "${REPO_DIR}/services/automation/backup/cron.example" "${R}/services/automation/backup/"
cp -rp "${REPO_DIR}/automation/machines" "${REPO_DIR}/automation/scripts" "${R}/automation/"
cp -p "${REPO_DIR}/automation/.gitignore" "${REPO_DIR}/automation/decree-go-rest.yml" "${R}/automation/"
mkdir -p "${R}/automation-examples/cron"
cp "${REPO_DIR}/automation-examples/cron/you-were-here.md" "${R}/automation-examples/cron/"
# An install from before workspace/.decree: an active cron, a migration and its ledger.
mkdir -p "${R}/automation/cron" "${R}/automation/migrations" "${R}/automation/secrets/rclone"
printf -- '---\ncron: "* * * * *"\nmachine: notify\n---\n' > "${R}/automation/cron/old.md"
printf -- '---\nmachine: notify\n---\n' > "${R}/automation/migrations/01-old.md"
printf '01-old.md\n' > "${R}/automation/processed.md"
printf 'secret\n' > "${R}/automation/secrets/rclone/rclone.conf"

run_init() { bash "${R}/services/automation/exist.initial.sh" >/dev/null 2>&1; }

run_init; _rc=$?
check "first run exits 0" "[[ $_rc -eq 0 ]]"

_shipped=$(cd "${R}/automation/machines" && ls *.yml | wc -l)
_seeded=$(cd "${P}/machines" 2>/dev/null && ls *.yml | wc -l)
check "every shipped machine is seeded" "[[ $_shipped -gt 0 && $_shipped -eq ${_seeded:-0} ]]"
check "scripts stay executable" "[[ -x '${P}/scripts/notify.sh' ]]"
check ".gitignore and decree-go-rest.yml are seeded" "[[ -f '${P}/.gitignore' && -f '${P}/decree-go-rest.yml' ]]"
for _d in runs/ store/ inbox/ attention/ '*.log' '.env*'; do
    check ".gitignore ignores ${_d}" "grep -qxF '${_d}' '${P}/.gitignore'"
done
check "lib/ is a mount point, not a copy" "[[ -d '${P}/lib' && -z \"\$(ls -A '${P}/lib')\" ]]"
check "an old install's cron moves over" "[[ -f '${P}/cron/old.md' && ! -e '${R}/automation/cron/old.md' ]]"
check "an old install's migration moves over" "[[ -f '${P}/migrations/01-old.md' ]]"
check "the migration ledger moves with them" "grep -qx '01-old.md' '${P}/processed.md'"
check "no secret lands under workspace/" "! grep -rqx 'secret' '${R}/volumes/workspace_data'"
check "the .env mount point is empty" "[[ -f '${P}/.env' && ! -s '${P}/.env' ]]"
check "the you-were-here digest is on by default" "cmp -s '${R}/automation-examples/cron/you-were-here.md' '${P}/cron/you-were-here.md'"

# The user's edits win, and their own files stay.
printf '# mine\n' > "${P}/machines/notify.yml"
printf 'mine\n' > "${P}/machines/mine.yml"
rm "${P}/machines/clean_runs.yml"
printf -- '---\ncron: "0 6 * * *"\nmachine: you_were_here\n---\n' > "${P}/cron/you-were-here.md"
run_init; _rc=$?
check "second run exits 0" "[[ $_rc -eq 0 ]]"
check "an edited machine is never overwritten" "[[ \"\$(cat '${P}/machines/notify.yml')\" == '# mine' ]]"
check "a user's own machine is left alone" "[[ -f '${P}/machines/mine.yml' ]]"
check "a removed shipped machine comes back, like a rendered file" "[[ -f '${P}/machines/clean_runs.yml' ]]"
check "an edited digest schedule is kept" "grep -qF '0 6 * * *' '${P}/cron/you-were-here.md'"

[[ "${TEST_SELFCHECK:-}" == 1 ]] && _fail "selfcheck canary (deliberate failure)"

echo ""
echo "=== Results: ${PASS} passed, ${FAIL} failed ==="
if [ "$FAIL" -gt 0 ]; then
    printf 'Failed: %s\n' "${FAIL_NAMES[*]}"
    exit 1
fi
