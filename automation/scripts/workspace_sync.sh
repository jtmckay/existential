#!/usr/bin/env bash
# workspace_sync — two-way sync workspace/ with a folder on the NAS or in
# Nextcloud, with rclone bisync; on a conflict the newer edit wins. Runs in
# automation-backup, which has the master .env (the Nextcloud credentials stay
# out of workspace/), /workspace and, given EXIST_NFS_PATH_WORKSPACE_SYNC_DATA,
# the NAS folder at /workspace-nas. The NAS wins over Nextcloud: one copy.
#
# Skipped: everything a .gitignore under workspace/ ignores (git itself decides,
# so its rules hold exactly), and every .git/. So decree's run state never
# syncs, and output kept local is one .gitignore line away.
#
# rclone refuses a sync that would delete over half the files on one side
# (--max-delete, default 50%). That run ends in too_many_deletes and the machine
# asks a person; until they answer, `held` makes every later run skip.
#
# WORKSPACE_SYNC_MODE: blank syncs; `force` (delete.sh) lets the deletes through;
# `resync` (keep.sh) merges both sides, which deletes nothing.
set -euo pipefail

WORKSPACE="${WORKSPACE_SYNC_DIR:-/workspace}"
mode="${WORKSPACE_SYNC_MODE:-}"
url="${EXIST_NEXTCLOUD_DOMAIN:-}"
user="${EXIST_NEXTCLOUD_USER:-}"
pass="${EXIST_NEXTCLOUD_APP_PASSWORD:-}"
nas_path="${EXIST_NFS_PATH_WORKSPACE_SYNC_DATA:-}"
nas_address="${EXIST_NFS_ADDRESS:-none}"

# generate-compose.ts mounts the NAS folder only given both keys; otherwise
# /workspace-nas is an unused local folder, never a sync target.
if [[ "$nas_path" == /* && -n "$nas_address" && "$nas_address" != none ]]; then
    remote="${WORKSPACE_SYNC_NAS:-/workspace-nas}"
elif [[ -z "$url" || -z "$user" || -z "$pass" ]]; then
    echo "No NAS folder (EXIST_NFS_PATH_WORKSPACE_SYNC_DATA) and no Nextcloud keys: nothing to sync."
    exit 0
fi
if [[ -z "$mode" && -e "$DECREE_STORE/held" ]]; then
    echo "A large delete is waiting for a person (decree status): not syncing until it is answered."
    exit 0
fi

if [[ -z "${remote:-}" ]]; then
    # A local Nextcloud is reached over the bridge, like every other container,
    # which also skips trusting Caddy's internal CA.
    if [[ "${EXIST_IS_NAS_NEXTCLOUD:-}" == true ]]; then
        url="http://nextcloud"
    elif [[ "$url" != *://* ]]; then
        url="https://${url}"
    fi
    # rclone reads its remote from the environment, so no secret is on a command line or on disk.
    export RCLONE_WEBDAV_URL="${url%/}/remote.php/dav/files/${user}"
    export RCLONE_WEBDAV_VENDOR="${RCLONE_WEBDAV_VENDOR:-nextcloud}"
    export RCLONE_WEBDAV_USER="$user"
    RCLONE_WEBDAV_PASS="$(printf '%s' "$pass" | rclone obscure -)"
    export RCLONE_WEBDAV_PASS
    remote=":webdav:${EXIST_NEXTCLOUD_WORKSPACE_DIR:-workspace}"
fi

# WebDAV drops file modes, and decree runs only executable scripts.
trap '[[ ! -d "$WORKSPACE/.decree/scripts" ]] || find "$WORKSPACE/.decree/scripts" -type f ! -perm -u+x -exec chmod +x {} +' EXIT

# The filter: .git/ anywhere, then every path git ignores, as rclone excludes
# (anchored, glob characters escaped). An empty repository outside workspace/
# lets git read workspace/'s .gitignore files whether or not it is a repo.
filters="$DECREE_RUN_DIR/filters"
git init -q "$DECREE_RUN_DIR/git"
{
    echo '- .git/**'
    git --git-dir="$DECREE_RUN_DIR/git/.git" --work-tree="$WORKSPACE" -C "$WORKSPACE" \
        ls-files -z --others --ignored --exclude-standard --directory \
        | while IFS= read -r -d '' _path; do
            _path=$(printf '%s' "$_path" | sed 's/[][\\*?{}]/\\&/g')
            [[ "$_path" == */ ]] && echo "- /${_path}**" || echo "- /${_path}"
        done
} > "$filters"

args=(bisync "$WORKSPACE" "$remote" --workdir "$DECREE_STORE/bisync" --filter-from "$filters"
      --resilient --recover --max-lock 10m --conflict-resolve newer --verbose)
# No listings for this remote yet (first run, or a new folder): merge, which deletes nothing.
if [[ "$mode" == resync || "$(cat "$DECREE_STORE/synced" 2>/dev/null)" != "$remote" ]]; then
    args+=(--resync)
fi
[[ "$mode" == force ]] && args+=(--force)

rclone mkdir "$remote"
set +e
rclone "${args[@]}" 2>&1 | tee "$DECREE_RUN_DIR/bisync.log"
rc=${PIPESTATUS[0]}
set -e
if grep -q 'too many deletes' "$DECREE_RUN_DIR/bisync.log"; then
    touch "$DECREE_STORE/held"
    echo too_many_deletes > "$DECREE_EVENT_FILE"
    exit 0
fi
[[ "$rc" -eq 0 ]] || exit "$rc"
echo "$remote" > "$DECREE_STORE/synced"
rm -f "$DECREE_STORE/held"
