#!/usr/bin/env bash
# Workspace Sync
#
# Bidirectionally syncs workspace/ with a workspace/ subfolder of the `nextcloud`
# seaweedfs bucket, so edits on either side — the host filesystem or the bucket
# (including through Nextcloud's own /S3 external-storage mount, since that
# bucket is what backs it) — show up on the other, and so that changes there
# become S3 events the decree webhook can route to matched file processors.
#
# Why the nextcloud bucket and not a dedicated one: it is already mounted into
# Nextcloud at /S3, so nothing written here needs a second mount to be browsable
# there. The trade is that the whole bucket is subscribed, so EVERY file event in
# it fires the webhook, not just ones under workspace/ — including ordinary
# Nextcloud usage. That is intentional, not an oversight: seaweedfs CAN scope the
# subscription by path (path_prefixes in nas/seaweedfs/notification.toml), but
# narrowing it to workspace/ would also silence the telegram and whisperx flows,
# which watch other prefixes of this same bucket.
#
# Why a sync and not a watch: writes to the workspace bind mount fire no events,
# and seaweedfs stores objects as needles inside its own volume files, so its data
# path cannot simply be pointed at workspace/. Copying the tree in is what makes
# the object store's own notification machinery apply to files you edit by hand.
#
# Why bisync and not sync: sync is one-way and would either overwrite whatever
# lands in the bucket (S3 -> local) or silently discard it (local -> S3). bisync
# tracks each side's prior state so it can tell which side actually changed.
# A file changed on both sides between runs becomes a numbered conflict copy
# rather than one side clobbering the other.
#
# workspace/ai/ is excluded, and that exclusion is load-bearing. It is where the
# agent automations write; syncing it would make every answer an event, and every
# event another run. OpenViking still indexes it straight off disk, so past
# output stays searchable without being able to trigger anything. It is baked
# into WORKSPACE_SYNC_EXCLUDE below rather than left to WORKSPACE_SYNC_IGNORE_FILE
# on purpose — a loop-breaker should not depend on someone maintaining a line in
# an editable ignore file.
#
# For your own excludes, drop a gitignore-style file at workspace/.syncignore
# (one glob pattern per line, same syntax as rclone --exclude, '#' comments) —
# no restart needed, it's read fresh every run.
#
# FIRST RUN: bisync has no prior state yet, so the first pass runs with --resync
# (below) and uploads the whole workspace in one go. Under minIO the webhook
# subscription was an admin-API call this routine had to defer until after that
# upload, or the baseline became one event per file. Seaweedfs subscribes from a
# static config file read at boot, so there is nothing to defer and nothing to
# queue — and the baseline therefore DOES fire an event per file. On a fresh
# install workspace/ is near-empty and the active processors match narrow
# patterns, so that is inbox churn rather than work. Nothing to do by hand.
#
#   ---
#   cron: "*/10 * * * *"
#   routine: workspace-sync
#   ---
set -euo pipefail

message_file="${message_file:-}"
message_id="${message_id:-}"
message_dir="${message_dir:-}"
chain="${chain:-}"
seq="${seq:-}"

WORKSPACE_DIR="${WORKSPACE_DIR:-/workspace}"
WORKSPACE_S3_BUCKET="${WORKSPACE_S3_BUCKET:-nextcloud}"
WORKSPACE_S3_PREFIX="${WORKSPACE_S3_PREFIX:-workspace}"
# bisync's own state (prior-run listings) — must survive between runs, so it
# lives on the runs/ bind mount rather than anywhere container-local.
WORKSPACE_BISYNC_WORKDIR="${WORKSPACE_BISYNC_WORKDIR:-/work/.decree/runs/.workspace-bisync}"
# Space-separated rclone --exclude patterns. Override to sync more or less, but
# keep ai/** unless you have broken the loop some other way.
WORKSPACE_SYNC_EXCLUDE="${WORKSPACE_SYNC_EXCLUDE:-ai/** .git/** node_modules/** .venv/** opencode.json}"
# User-editable excludes, .gitignore-style: one rclone glob pattern per line.
# Optional — skipped entirely if the file doesn't exist.
WORKSPACE_SYNC_IGNORE_FILE="${WORKSPACE_SYNC_IGNORE_FILE:-${WORKSPACE_DIR}/.syncignore}"

if [[ "${DECREE_PRE_CHECK:-}" == "true" ]]; then
    command -v rclone >/dev/null 2>&1     || { echo "rclone not found" >&2; exit 1; }
    [[ -d "${WORKSPACE_DIR}" ]]           || { echo "${WORKSPACE_DIR} is not a directory — is ../../workspace mounted read-write into decree-backup?" >&2; exit 1; }
    [[ -n "${S3_ACCESS_KEY:-}" ]]         || { echo "S3_ACCESS_KEY not set" >&2; exit 1; }
    [[ -n "${S3_SECRET_KEY:-}" ]]         || { echo "S3_SECRET_KEY not set" >&2; exit 1; }
    exit 0
fi

# Configured entirely from env, so nothing has to
# be written into automation/secrets/rclone/rclone.conf.
export RCLONE_CONFIG_S3_TYPE=s3
export RCLONE_CONFIG_S3_PROVIDER=Other
export RCLONE_CONFIG_S3_ENV_AUTH=false
export RCLONE_CONFIG_S3_ENDPOINT="${S3_URL:-http://seaweedfs:8333}"
export RCLONE_CONFIG_S3_REGION="${S3_REGION:-us-east-1}"
export RCLONE_CONFIG_S3_ACCESS_KEY_ID="${S3_ACCESS_KEY}"
export RCLONE_CONFIG_S3_SECRET_ACCESS_KEY="${S3_SECRET_KEY}"

_remote="s3:${WORKSPACE_S3_BUCKET}/${WORKSPACE_S3_PREFIX}"

if ! rclone lsd "s3:${WORKSPACE_S3_BUCKET}" >/dev/null 2>&1; then
    echo "Bucket '${WORKSPACE_S3_BUCKET}' does not exist."
    echo "It should already exist as Nextcloud's external-storage bucket — check"
    echo "EXIST_IS_NAS_SEAWEEDFS is enabled — seaweedfs pre-creates this bucket on"
    echo "startup via its -bucket flag (nas/seaweedfs/docker-compose.exist.yml)."
    exit 1
fi

mkdir -p "${WORKSPACE_BISYNC_WORKDIR}"

_excludes=()
for _pat in ${WORKSPACE_SYNC_EXCLUDE}; do
    _excludes+=(--exclude "$_pat")
done
if [[ -f "${WORKSPACE_SYNC_IGNORE_FILE}" ]]; then
    _excludes+=(--exclude-from "${WORKSPACE_SYNC_IGNORE_FILE}")
fi

_bisync() {
    rclone bisync "${WORKSPACE_DIR}" "${_remote}" \
        "${_excludes[@]}" \
        --workdir "${WORKSPACE_BISYNC_WORKDIR}" \
        --conflict-resolve newer \
        --resilient \
        --recover \
        --fast-list \
        --stats-one-line \
        --stats 0 \
        --verbose \
        "$@"
}

echo "Syncing ${WORKSPACE_DIR} <-> ${_remote}"
echo "Excluding: ${WORKSPACE_SYNC_EXCLUDE}"
[[ -f "${WORKSPACE_SYNC_IGNORE_FILE}" ]] && echo "Excluding (from ${WORKSPACE_SYNC_IGNORE_FILE}): $(tr '\n' ' ' < "${WORKSPACE_SYNC_IGNORE_FILE}")"

_log="$(mktemp)"
trap 'rm -f "$_log"' EXIT

# `if pipeline; then` — not `pipeline | grep ...` — because piping through
# grep for display would make grep's match/no-match the thing `if` sees
# instead of bisync's own exit code, and a clean run with nothing to report
# would then misread as a failure.
if _bisync 2>&1 | tee "$_log"; then
    grep -E 'Copied|Deleted|Updated|Transferred|Conflict' "$_log" || true
elif grep -qi 'first bisync run\|cannot find prior\|empty.*listing' "$_log"; then
    # Several different-worded guards land here (rclone has separate checks for
    # a missing, current-empty, AND prior-empty listing on either path), all
    # recovered the same safe way:
    #   - no prior state at all (truly the first run)
    #   - a listing — current or prior — came back empty (workspace/ excludes
    #     ai/, which can legitimately be the only thing in there — bisync can't
    #     tell that apart from a failed mount, so it refuses to guess)
    # --resync never deletes to reconcile — a file missing from one side is
    # copied from the other, not treated as a delete — so retrying with it here
    # cannot lose data even if the empty side turns out to be a real problem;
    # it just means nothing uploads from that side until the next real run.
    echo "No usable prior bisync state — initializing baseline with --resync."
    if ! _bisync --resync 2>&1 | tee "$_log"; then
        echo "bisync --resync failed — see above." >&2
        exit 1
    fi
    grep -E 'Copied|Deleted|Updated|Transferred' "$_log" || true

else
    echo "bisync failed — see above." >&2
    exit 1
fi

echo "Sync complete."
