---
name: workspace_sync
x-exist-topic: host
x-exist-project: backup
machine:
  description: Two-way sync workspace/ with a folder on the NAS or in Nextcloud, newest edit winning, skipping what any .gitignore ignores and every .git/, and asking a person before a large delete.
  state_files:
    bisync: rclone bisync's listings and lock. Every state reads and writes it.
    synced: The remote the listings in bisync/ are for; a different one makes workspace_sync merge (--resync) instead of sync.
    held: Present while a large delete waits for a person; workspace_sync skips until delete or keep removes it.
  initial: sync
  states:
    sync:
      invoke: workspace_sync
      transitions: {done: done, too_many_deletes: confirm_deletes}
    # rclone refused a sync that would delete over half the files on one side.
    confirm_deletes:
      invoke:
        reply:
          question: >-
            A workspace sync would delete over half the files on one side, so it stopped and deleted nothing. Its run log lists them.
          notify: ask
      transitions:
        delete:
          target: delete
          description: The deletes are intended; sync them.
        keep:
          target: keep
          description: Keep every file; copy each missing one back from the side that still has it.
      emits: [notify]
    delete:
      invoke: delete
      transitions: {done: done}
    keep:
      invoke: keep
      transitions: {done: done}
    done: {final: true}
    failed: {final: true}
scripts:
  ask.sh: |
    #!/usr/bin/env bash
    # workspace_sync/ask — tell someone a large delete is waiting, and how to answer.
    set -euo pipefail
    {
        echo "$DECREE_QUESTION"
        echo
        for _event in $DECREE_EVENTS; do
            [[ "$_event" == error ]] && continue
            echo "docker exec automation-backup decree reply $DECREE_WAIT_ID $_event"
        done
    } | decree emit --machine notify --param ntfy_topic=host --param ntfy_title="workspace sync: large delete held" >/dev/null
  delete.sh: |
    #!/usr/bin/env bash
    WORKSPACE_SYNC_MODE=force exec "$(dirname "$0")/workspace_sync.sh"
  keep.sh: |
    #!/usr/bin/env bash
    WORKSPACE_SYNC_MODE=resync exec "$(dirname "$0")/workspace_sync.sh"
  workspace_sync.sh: |
    #!/usr/bin/env bash
    # workspace_sync — two-way sync workspace/ with a folder on the NAS or in
    # Nextcloud, with rclone bisync; on a conflict the newer edit wins. Runs in
    # automation-backup, which has the master .env (the Nextcloud credentials stay
    # out of workspace/), /workspace and, given EXIST_NFS_SHARE_WORKSPACE,
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
    nas_path="${EXIST_NFS_SHARE_WORKSPACE:-}"
    nas_address="${EXIST_NFS_ADDRESS:-none}"

    # generate-compose.ts mounts the NAS folder only given both keys; otherwise
    # /workspace-nas is an unused local folder, never a sync target.
    if [[ "$nas_path" == /* && -n "$nas_address" && "$nas_address" != none ]]; then
        remote="${WORKSPACE_SYNC_NAS:-/workspace-nas}"
    elif [[ -z "$url" || -z "$user" || -z "$pass" ]]; then
        echo "No NAS folder (EXIST_NFS_SHARE_WORKSPACE) and no Nextcloud keys: nothing to sync."
        exit 0
    fi
    if [[ -z "$mode" && -e "$DECREE_STATE_DIR/held" ]]; then
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

    # The filter: .git/ anywhere, then every path git ignores, as rclone excludes
    # (anchored, glob characters escaped). An empty repository outside workspace/
    # lets git read workspace/'s .gitignore files whether or not it is a repo.
    filters="$DECREE_RUN_DIR/filters"
    git init -q "$DECREE_RUN_DIR/git"
    {
        echo '- .git/**'
        # decree's code is installed with `decree install`: no other copy of the
        # workspace ever brings a plugin, a machine or lib in, and none is sent out.
        printf -- '- /.decree/%s/**\n' plugins machines lib
        git --git-dir="$DECREE_RUN_DIR/git/.git" --work-tree="$WORKSPACE" -C "$WORKSPACE" \
            ls-files -z --others --ignored --exclude-standard --directory \
            | while IFS= read -r -d '' _path; do
                _path=$(printf '%s' "$_path" | sed 's/[][\\*?{}]/\\&/g')
                [[ "$_path" == */ ]] && echo "- /${_path}**" || echo "- /${_path}"
            done
    } > "$filters"

    args=(bisync "$WORKSPACE" "$remote" --workdir "$DECREE_STATE_DIR/bisync" --filter-from "$filters"
          --resilient --recover --max-lock 10m --conflict-resolve newer --verbose)
    # No listings for this remote yet (first run, or a new folder): merge, which deletes nothing.
    if [[ "$mode" == resync || "$(cat "$DECREE_STATE_DIR/synced" 2>/dev/null)" != "$remote" ]]; then
        args+=(--resync)
    fi
    [[ "$mode" == force ]] && args+=(--force)

    rclone mkdir "$remote"
    set +e
    rclone "${args[@]}" 2>&1 | tee "$DECREE_RUN_DIR/bisync.log"
    rc=${PIPESTATUS[0]}
    set -e
    if grep -q 'too many deletes' "$DECREE_RUN_DIR/bisync.log"; then
        touch "$DECREE_STATE_DIR/held"
        echo too_many_deletes > "$DECREE_EVENT_FILE"
        exit 0
    fi
    [[ "$rc" -eq 0 ]] || exit "$rc"
    echo "$remote" > "$DECREE_STATE_DIR/synced"
    rm -f "$DECREE_STATE_DIR/held"
cron:
  workspace-sync.md: |
    ---
    cron: "* * * * *"
    machine: workspace_sync
    ---

    Two-way syncs `workspace/` with one other copy, every minute, so it is the same tree
    wherever you edit it. A file changed on both sides since the last run keeps the newer edit.

    - **On the NAS**: give `EXIST_NFS_SHARE_WORKSPACE` a folder on the NAS (asked
      when `./existential.sh` first sees `automation-backup` on with a NAS). It wins over Nextcloud.
    - **In Nextcloud**: set `EXIST_NEXTCLOUD_DOMAIN`, `EXIST_NEXTCLOUD_USER` and
      `EXIST_NEXTCLOUD_APP_PASSWORD` in `.env` (an app password, from Nextcloud's Settings >
      Security). The folder is `EXIST_NEXTCLOUD_WORKSPACE_DIR` (default `workspace`).

    Then `docker compose up -d automation-backup`. With neither, each run does nothing. The first
    run with a new other end merges both sides and deletes nothing.

    Never synced: anything a `.gitignore` under `workspace/` ignores, and every `.git/`. That
    keeps decree's run state local; add a line to keep anything else local.

    A run that would delete over half the files on one side deletes nothing and asks you instead
    (ntfy, and `decree status` in automation-backup). Until you answer `delete` or `keep`, later
    runs skip.
---
# workspace_sync

Two-way sync workspace/ with a folder on the NAS or in Nextcloud, newest edit winning, skipping what any .gitignore ignores and every .git/, and asking a person before a large delete.
