#!/usr/bin/env bash
# test-workspace-sync.sh — automation/scripts/workspace_sync.sh two-way syncs a
# workspace with a folder over WebDAV: a remote file comes down, nothing a
# .gitignore ignores and no .git/ goes up, a script that comes down is
# executable, and a sync that would delete most files deletes nothing and holds
# until a person answers.
#
# Runs the real script against `rclone serve webdav` on localhost, so it needs
# rclone and git (the adhoc image has both). Everything lives in a scratch dir
# removed in the trap.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
[[ -f "${REPO_DIR}/.env.exist.shared" ]] || REPO_DIR="/repo"
SYNC="${REPO_DIR}/automation/scripts/workspace_sync.sh"

PASS=0; FAIL=0; FAIL_NAMES=()
_ok()   { printf '  PASS  %s\n' "$1"; PASS=$((PASS + 1)); }
_fail() { printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; FAIL=$((FAIL + 1)); FAIL_NAMES+=("$1"); }
check() { if eval "$2"; then _ok "$1"; else _fail "$1" "$2"; fi; }

for _bin in rclone git; do
    command -v "$_bin" >/dev/null || { echo "workspace-sync: needs ${_bin} (run it through ./existential.sh test unit)"; exit 1; }
done

TMP="$(mktemp -d)"
trap 'kill "$DAV_PID" 2>/dev/null; rm -rf "$TMP"' EXIT
WS="${TMP}/workspace"
DAV="${TMP}/dav"
REMOTE="${DAV}/remote.php/dav/files/sync-user/workspace"
STORE="${TMP}/store"
mkdir -p "$WS" "$REMOTE" "$STORE"

PORT=$((20000 + RANDOM % 20000))
rclone serve webdav "$DAV" --addr "127.0.0.1:${PORT}" --user sync-user --pass app-pass >/dev/null 2>&1 &
DAV_PID=$!
# Remote-side writes go through the server, as Nextcloud's would, so its listing cache stays true.
put() { printf '%s' "$2" | curl -sf -u sync-user:app-pass -T - "http://127.0.0.1:${PORT}/remote.php/dav/files/sync-user/workspace/$1"; }
for _ in $(seq 50); do curl -s -o /dev/null "http://127.0.0.1:${PORT}/" && break; sleep 0.1; done

mkdir -p "${TMP}/runs"
sync() {         # [VAR=value ...]: one run with a fresh run dir; prints its event
    local run; run=$(mktemp -d "${TMP}/runs/XXXX")
    : > "${run}/event"
    # rclone serve webdav speaks plain WebDAV, without Nextcloud's checksums.
    env RCLONE_WEBDAV_VENDOR=other EXIST_NEXTCLOUD_DOMAIN="http://127.0.0.1:${PORT}" EXIST_NEXTCLOUD_USER=sync-user \
        EXIST_NEXTCLOUD_APP_PASSWORD=app-pass EXIST_NEXTCLOUD_WORKSPACE_DIR=workspace \
        EXIST_IS_NAS_NEXTCLOUD=false WORKSPACE_SYNC_DIR="$WS" DECREE_STORE="$STORE" \
        DECREE_RUN_DIR="$run" DECREE_EVENT_FILE="${run}/event" "$@" \
        bash "$SYNC" > "${run}/log" 2>&1 || { echo "exit $?"; return; }
    cat "${run}/event"
}

# Unconfigured: nothing to do, and still a clean exit.
check "a blank domain is a no-op" "[[ \"\$(sync EXIST_NEXTCLOUD_DOMAIN=)\" == '' && -z \"\$(ls -A '$REMOTE')\" ]]"

mkdir -p "$WS"/{notes,ai,sub,.git,notes/.git,.decree/runs/r1,.decree/scripts}
for _f in notes/a.md notes/b.md notes/c.md notes/d.md secret.txt ai/out.md sub/keep.md sub/x.tmp \
          .git/config notes/.git/HEAD .decree/runs/r1/log '.decree/scripts/odd [name].sh'; do
    echo "$_f" > "${WS}/${_f}"
done
printf 'secret.txt\nai/\n' > "${WS}/.gitignore"
printf '*.tmp\n' > "${WS}/sub/.gitignore"
printf 'runs/\n' > "${WS}/.decree/.gitignore"

check "the first run merges" "[[ \"\$(sync)\" == '' ]]"
check "a workspace file is uploaded" "[[ -f '${REMOTE}/notes/a.md' && -f '${REMOTE}/sub/keep.md' ]]"
check "a file with glob characters in its name is uploaded" "[[ -f '${REMOTE}/.decree/scripts/odd [name].sh' ]]"
check "a root .gitignore'd file is not uploaded" "[[ ! -e '${REMOTE}/secret.txt' ]]"
check "a .gitignore'd directory is not uploaded" "[[ ! -e '${REMOTE}/ai' ]]"
check "a nested .gitignore is honoured" "[[ ! -e '${REMOTE}/sub/x.tmp' ]]"
check "decree's run state is not uploaded" "[[ ! -e '${REMOTE}/.decree/runs' ]]"
check "no .git/ is uploaded, at any depth" "[[ ! -e '${REMOTE}/.git' && ! -e '${REMOTE}/notes/.git' ]]"

# A file and a script created on the remote side come down; the script is executable.
put notes/new.md new
put .decree/scripts/hello.sh '#!/usr/bin/env bash'
check "the next run syncs" "[[ \"\$(sync)\" == '' ]]"
check "a remote file appears in the workspace" "[[ \"\$(cat '${WS}/notes/new.md' 2>/dev/null)\" == new ]]"
check "a script that came down is executable" "[[ -x '${WS}/.decree/scripts/hello.sh' ]]"

# Delete most of the workspace: rclone refuses, and the machine asks a person.
rm -f "$WS"/notes/{a,b,c,d,new}.md "${WS}/sub/keep.md" "${WS}/.decree/scripts/hello.sh"
check "a large delete ends in too_many_deletes" "[[ \"\$(sync)\" == too_many_deletes ]]"
check "nothing was deleted remotely" "[[ -f '${REMOTE}/notes/a.md' && -f '${REMOTE}/notes/new.md' ]]"
check "the hold is recorded" "[[ -e '${STORE}/held' ]]"
put notes/later.md later
check "a held sync skips" "[[ \"\$(sync)\" == '' && ! -e '${WS}/notes/later.md' ]]"
check "keep restores every file" \
    "[[ \"\$(sync WORKSPACE_SYNC_MODE=resync)\" == '' && -f '${WS}/notes/a.md' && -f '${WS}/notes/later.md' && ! -e '${STORE}/held' ]]"
rm -f "$WS"/notes/*.md "${WS}/sub/keep.md"
check "a second large delete is held too" "[[ \"\$(sync)\" == too_many_deletes && -f '${REMOTE}/notes/a.md' ]]"
check "delete lets the deletes through" \
    "[[ \"\$(sync WORKSPACE_SYNC_MODE=force)\" == '' && ! -e '${REMOTE}/notes/a.md' && ! -e '${STORE}/held' ]]"

[[ "${TEST_SELFCHECK:-}" == 1 ]] && _fail "selfcheck canary (deliberate failure)"

echo ""
echo "=== Results: ${PASS} passed, ${FAIL} failed ==="
if [ "$FAIL" -gt 0 ]; then
    printf 'Failed: %s\n' "${FAIL_NAMES[*]}"
    for _log in "${TMP}"/runs/*/log; do echo "--- ${_log#"$TMP/"}"; cat "$_log"; done
    exit 1
fi
