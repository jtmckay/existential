#!/usr/bin/env bash
# Workspace Sync
#
# Bidirectionally syncs workspace/ with a workspace/ subfolder of the `nextcloud`
# MinIO bucket, so edits on either side — the host filesystem or the bucket
# (including through Nextcloud's own /S3 external-storage mount, since that
# bucket is what backs it) — show up on the other, and so that changes there
# become S3 events the decree webhook can route to matched file processors.
#
# Why the nextcloud bucket and not a dedicated one: it is already mounted into
# Nextcloud at /S3, so nothing written here needs a second mount to be browsable
# there. The trade is that subscribing this bucket to MinIO's webhook (done
# automatically below, once, right after the first successful sync) means
# EVERY file event in it fires the webhook, not just ones under workspace/ —
# including ordinary Nextcloud usage. That is intentional here, not an
# oversight.
#
# Why a sync and not a watch: writes to the workspace bind mount fire no S3
# events, and MinIO's single-drive mode writes xl.meta per object, so its drive
# path cannot simply be pointed at workspace/. Copying the tree in is what makes
# MinIO's own notification machinery apply to files you edit by hand.
#
# Why bisync and not sync: sync is one-way and would either overwrite whatever
# lands in MinIO (S3 -> local) or silently discard it (local -> S3). bisync
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
# FIRST RUN: bisync has no prior state yet, so the first pass runs with
# --resync (below) and uploads the whole workspace in one go. Subscribing the
# bucket to the webhook BEFORE that would turn that bulk upload into one event
# per file arriving at once — so the subscription is queued as a follow-up
# message (via minio-bucket-webhook) only after that first sync succeeds,
# never before. Nothing to do by hand; this is what makes it safe for
# workspace-sync's cron to just be on from the start.
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
    [[ -n "${MINIO_ROOT_USER:-}" ]]       || { echo "MINIO_ROOT_USER not set" >&2; exit 1; }
    [[ -n "${MINIO_ROOT_PASSWORD:-}" ]]   || { echo "MINIO_ROOT_PASSWORD not set" >&2; exit 1; }
    exit 0
fi

# Configured entirely from env, the way minio-bucket does it, so nothing has to
# be written into automation/secrets/rclone/rclone.conf.
export RCLONE_CONFIG_MINIO_TYPE=s3
export RCLONE_CONFIG_MINIO_PROVIDER=Minio
export RCLONE_CONFIG_MINIO_ENV_AUTH=false
export RCLONE_CONFIG_MINIO_ENDPOINT="${MINIO_URL:-http://minio:9000}"
export RCLONE_CONFIG_MINIO_REGION="${MINIO_REGION:-us-east-1}"
export RCLONE_CONFIG_MINIO_ACCESS_KEY_ID="${MINIO_ROOT_USER}"
export RCLONE_CONFIG_MINIO_SECRET_ACCESS_KEY="${MINIO_ROOT_PASSWORD}"

_remote="minio:${WORKSPACE_S3_BUCKET}/${WORKSPACE_S3_PREFIX}"

if ! rclone lsd "minio:${WORKSPACE_S3_BUCKET}" >/dev/null 2>&1; then
    echo "Bucket '${WORKSPACE_S3_BUCKET}' does not exist."
    echo "It should already exist as Nextcloud's external-storage bucket — check"
    echo "EXIST_IS_NAS_MINIO / EXIST_IS_NAS_NEXTCLOUD are both enabled and the"
    echo "01-minio-create-nextcloud-bucket migration has run."
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

    # Only safe to subscribe now that the bulk baseline upload above is done —
    # see the FIRST RUN note at the top of this file. minio-bucket-webhook is
    # idempotent, so it's fine that this branch (and therefore this queue) can
    # in principle run again later too (any run that hits an empty-listing
    # guard takes this same path, not only the true first run).
    _outbox="${OUTBOX_DIR:-/work/.decree/outbox}"
    mkdir -p "$_outbox"
    cat > "${_outbox}/workspace-sync-subscribe-$(date +%s%N).md" << EOF
---
routine: minio-bucket-webhook
BUCKET: ${WORKSPACE_S3_BUCKET}
---
EOF
    echo "Queued: subscribe ${WORKSPACE_S3_BUCKET} to the decree webhook."
else
    echo "bisync failed — see above." >&2
    exit 1
fi

echo "Sync complete."
