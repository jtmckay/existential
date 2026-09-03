#!/usr/bin/env bash
# Workspace Sync
#
# Mirrors workspace/ into a MinIO bucket so that changes there become S3 events,
# which the decree webhook turns into minio-router runs and, from there, into
# matched processors.
#
# Why a sync and not a watch: writes to the workspace bind mount fire no S3
# events, and MinIO's single-drive mode writes xl.meta per object, so its drive
# path cannot simply be pointed at workspace/. Copying the tree in is what makes
# MinIO's own notification machinery — which already exists and is already wired
# to the webhook — apply to files you edit by hand.
#
# workspace/ai/ is excluded, and that exclusion is load-bearing. It is where the
# agent automations write; syncing it would make every answer an event, and every
# event another run. OpenViking still indexes it straight off disk, so past
# output stays searchable without being able to trigger anything.
#
# FIRST RUN: sync once BEFORE subscribing the bucket to the webhook. rclone
# uploads the whole workspace on the first pass, and against a subscribed bucket
# that is one event per file arriving at once. Order it:
#
#   printf -- '---\nroutine: workspace-sync\n---\n' \
#     > services/decree/decree-backup/inbox/sync-once.md   # wait for it to finish, then:
#   docker exec minio mc event add minio/workspace arn:minio:sqs::DECREE:webhook \
#     --event put,delete
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
WORKSPACE_BUCKET="${WORKSPACE_BUCKET:-workspace}"
# Space-separated rclone --exclude patterns. Override to sync more or less, but
# keep ai/** unless you have broken the loop some other way.
WORKSPACE_SYNC_EXCLUDE="${WORKSPACE_SYNC_EXCLUDE:-ai/** .git/** node_modules/** .venv/** opencode.json}"

if [[ "${DECREE_PRE_CHECK:-}" == "true" ]]; then
    command -v rclone >/dev/null 2>&1     || { echo "rclone not found" >&2; exit 1; }
    [[ -d "${WORKSPACE_DIR}" ]]           || { echo "${WORKSPACE_DIR} is not a directory — is ../../workspace mounted into decree-backup?" >&2; exit 1; }
    [[ -n "${MINIO_ROOT_USER:-}" ]]       || { echo "MINIO_ROOT_USER not set" >&2; exit 1; }
    [[ -n "${MINIO_ROOT_PASSWORD:-}" ]]   || { echo "MINIO_ROOT_PASSWORD not set" >&2; exit 1; }
    exit 0
fi

# Configured entirely from env, the way minio-bucket does it, so nothing has to
# be written into automations/secrets/rclone/rclone.conf.
export RCLONE_CONFIG_MINIO_TYPE=s3
export RCLONE_CONFIG_MINIO_PROVIDER=Minio
export RCLONE_CONFIG_MINIO_ENV_AUTH=false
export RCLONE_CONFIG_MINIO_ENDPOINT="${MINIO_URL:-http://minio:9000}"
export RCLONE_CONFIG_MINIO_REGION="${MINIO_REGION:-us-east-1}"
export RCLONE_CONFIG_MINIO_ACCESS_KEY_ID="${MINIO_ROOT_USER}"
export RCLONE_CONFIG_MINIO_SECRET_ACCESS_KEY="${MINIO_ROOT_PASSWORD}"

if ! rclone lsd "minio:${WORKSPACE_BUCKET}" >/dev/null 2>&1; then
    echo "Bucket '${WORKSPACE_BUCKET}' does not exist."
    echo "Create it by activating migrations.example/03-create-workspace-bucket.md,"
    echo "or drop a message naming routine minio-bucket with BUCKET=${WORKSPACE_BUCKET}."
    exit 1
fi

_excludes=()
for _pat in ${WORKSPACE_SYNC_EXCLUDE}; do
    _excludes+=(--exclude "$_pat")
done

echo "Syncing ${WORKSPACE_DIR} → minio:${WORKSPACE_BUCKET}"
echo "Excluding: ${WORKSPACE_SYNC_EXCLUDE}"

rclone sync "${WORKSPACE_DIR}" "minio:${WORKSPACE_BUCKET}" \
    "${_excludes[@]}" \
    --fast-list \
    --stats-one-line \
    --stats 0 \
    --verbose 2>&1 | grep -E 'Copied|Deleted|Updated|Transferred|ERROR' || true

echo "Sync complete."
