#!/usr/bin/env bash
# minio.sh — source this at the top of any routine that needs a minIO file.
#
# Prerequisites (declare before sourcing):
#   message_file  — standard decree var (already set by the runtime)
#   rclone_src    — rclone remote name for minIO (routine param, default: "minio")
#
# After sourcing:
#   MINIO_EVENT_NAME   e.g. "s3:ObjectCreated:Put"
#   MINIO_BUCKET       bucket name
#   MINIO_OBJECT_KEY   object path within the bucket
#   MINIO_LOCAL_FILE   absolute path to the downloaded temp file
#                      empty string for ObjectRemoved and unhandled events
#
# The temp file (and its directory) are removed automatically on EXIT.
#
# Typical routine usage:
#
#   rclone_src="${rclone_src:-minio}"
#   # shellcheck source=../lib/minio.sh
#   source "$(dirname "${BASH_SOURCE[0]}")/../lib/minio.sh"
#
#   if [ -z "$MINIO_LOCAL_FILE" ]; then
#       echo "No file to process (event: $MINIO_EVENT_NAME)."
#       exit 0
#   fi
#
#   # operate on "$MINIO_LOCAL_FILE" ...
#   # cleanup is automatic — no need to rm

_minio_json=$(awk 'NR==1 && /^---$/{skip=1; next} skip && /^---$/{skip=0; next} !skip' \
    "${message_file:-/dev/null}" | sed '/./,$!d')

if [ -z "$_minio_json" ]; then
    echo "[minio] Empty message body — nothing to process." >&2
    exit 1
fi

MINIO_EVENT_NAME=$(echo "$_minio_json" | jq -r '.EventName // empty')
_minio_key=$(echo "$_minio_json"       | jq -r '.Key        // empty')

if [ -z "$MINIO_EVENT_NAME" ] || [ -z "$_minio_key" ]; then
    echo "[minio] Could not parse EventName or Key — verify minIO is sending S3-compatible events." >&2
    echo "[minio] Payload: $_minio_json" >&2
    exit 1
fi

MINIO_BUCKET="${_minio_key%%/*}"
MINIO_OBJECT_KEY="${_minio_key#*/}"
export MINIO_EVENT_NAME MINIO_BUCKET MINIO_OBJECT_KEY

echo "[minio] Event:  $MINIO_EVENT_NAME"
echo "[minio] Object: $MINIO_BUCKET/$MINIO_OBJECT_KEY"

MINIO_LOCAL_FILE=""

if [[ "$MINIO_EVENT_NAME" == *"ObjectCreated"* ]]; then
    _minio_tmp_dir=$(mktemp -d)
    _minio_filename=$(basename "$MINIO_OBJECT_KEY")
    MINIO_LOCAL_FILE="$_minio_tmp_dir/$_minio_filename"

    # shellcheck disable=SC2064
    trap "rm -rf '$_minio_tmp_dir'" EXIT

    echo "[minio] Downloading ${rclone_src:-minio}:$MINIO_BUCKET/$MINIO_OBJECT_KEY → $MINIO_LOCAL_FILE"
    rclone copyto \
        "${rclone_src:-minio}:$MINIO_BUCKET/$MINIO_OBJECT_KEY" \
        "$MINIO_LOCAL_FILE" \
        --config /secrets/rclone/rclone.conf \
        --progress \
        --stats-one-line
    echo "[minio] Ready: $MINIO_LOCAL_FILE"

elif [[ "$MINIO_EVENT_NAME" == *"ObjectRemoved"* ]]; then
    echo "[minio] Delete event — no file to download."

else
    echo "[minio] Unhandled event type '$MINIO_EVENT_NAME'."
fi

export MINIO_LOCAL_FILE
unset _minio_json _minio_key _minio_tmp_dir _minio_filename
