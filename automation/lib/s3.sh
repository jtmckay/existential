#!/usr/bin/env bash
# s3.sh — source this at the top of any routine that needs a file from the object store.
#
# Prerequisites (declare before sourcing):
#   message_file  — standard decree var (already set by the runtime)
#   rclone_src    — rclone remote name for the object store (routine param, default: "s3")
#
# After sourcing:
#   S3_EVENT_TYPE   "create" | "update" | "delete" | "rename"
#   S3_FILE_ACTION  "created" | "removed"  (the same clean strings s3-router emits)
#   S3_BUCKET       bucket name
#   S3_OBJECT_KEY   object path within the bucket
#   S3_LOCAL_FILE   absolute path to the downloaded temp file
#                   empty string for removals and unhandled events
#
# The temp file (and its directory) are removed automatically on EXIT.
#
# The event shape is SeaweedFS's filer webhook, not S3 bucket notifications — see
# the header of shared_routines/s3-router.sh for why, and for the two things that
# follow from it: `key` is a filer path under /buckets/, and directories raise
# events of their own (dropped here).
#
# A rename carries two paths and this helper can only hand back one file, so it
# reports the DESTINATION (S3_FILE_ACTION=created). A routine that has to react to
# the source path too should read the raw event instead of using this helper.
#
# Typical routine usage:
#
#   rclone_src="${rclone_src:-s3}"
#   # shellcheck source=../lib/s3.sh
#   source "$(dirname "${BASH_SOURCE[0]}")/../lib/s3.sh"
#
#   if [ -z "$S3_LOCAL_FILE" ]; then
#       echo "No file to process (event: $S3_EVENT_TYPE)."
#       exit 0
#   fi
#
#   # operate on "$S3_LOCAL_FILE" ...
#   # cleanup is automatic — no need to rm

_s3_json=$(awk 'NR==1 && /^---$/{skip=1; next} skip && /^---$/{skip=0; next} !skip' \
    "${message_file:-/dev/null}" | sed '/./,$!d')

if [ -z "$_s3_json" ]; then
    echo "[s3] Empty message body — nothing to process." >&2
    exit 1
fi

S3_EVENT_TYPE=$(echo "$_s3_json" | jq -r '.event_type // empty')
_s3_key=$(echo "$_s3_json"       | jq -r '.key        // empty')

if [ -z "$S3_EVENT_TYPE" ] || [ -z "$_s3_key" ]; then
    echo "[s3] Could not parse event_type or key — verify seaweedfs is sending filer webhook events." >&2
    echo "[s3] Payload: $_s3_json" >&2
    exit 1
fi

# Directories raise events too, and there is no file behind one.
if [ "$(echo "$_s3_json" | jq -r '.message.new_entry.is_directory // false')" = "true" ] \
   || [ "$(echo "$_s3_json" | jq -r '.message.old_entry.is_directory // false')" = "true" ]; then
    echo "[s3] Directory event ($S3_EVENT_TYPE $_s3_key) — nothing to process."
    exit 0
fi

case "$S3_EVENT_TYPE" in
    create|update)
        S3_FILE_ACTION="created"
        ;;
    delete)
        S3_FILE_ACTION="removed"
        ;;
    rename)
        # Report the destination — see the header.
        S3_FILE_ACTION="created"
        _s3_new_parent=$(echo "$_s3_json" | jq -r '.message.new_parent_path // empty')
        _s3_new_name=$(echo "$_s3_json"   | jq -r '.message.new_entry.name  // empty')
        if [ -n "$_s3_new_parent" ] && [ -n "$_s3_new_name" ]; then
            _s3_key="${_s3_new_parent%/}/${_s3_new_name}"
        else
            echo "[s3] Rename event without a usable destination." >&2
            exit 1
        fi
        ;;
    *)
        S3_FILE_ACTION=""
        ;;
esac

# "/buckets/nextcloud/workspace/f.pdf" -> "nextcloud/workspace/f.pdf"
_s3_path="${_s3_key#/buckets/}"
S3_BUCKET="${_s3_path%%/*}"
S3_OBJECT_KEY="${_s3_path#*/}"
export S3_EVENT_TYPE S3_FILE_ACTION S3_BUCKET S3_OBJECT_KEY

echo "[s3] Event:  $S3_EVENT_TYPE"
echo "[s3] Object: $S3_BUCKET/$S3_OBJECT_KEY"

S3_LOCAL_FILE=""

if [ "$S3_FILE_ACTION" = "created" ]; then
    _s3_tmp_dir=$(mktemp -d "${message_dir:-/work/.decree/runs}/tmp.XXXXXX")
    _s3_filename=$(basename "$S3_OBJECT_KEY")
    S3_LOCAL_FILE="$_s3_tmp_dir/$_s3_filename"

    # shellcheck disable=SC2064
    trap "rm -rf '$_s3_tmp_dir'" EXIT

    echo "[s3] Downloading ${rclone_src:-s3}:$S3_BUCKET/$S3_OBJECT_KEY → $S3_LOCAL_FILE"
    rclone copyto \
        "${rclone_src:-s3}:$S3_BUCKET/$S3_OBJECT_KEY" \
        "$S3_LOCAL_FILE" \
        --config /secrets/rclone/rclone.conf \
        --progress \
        --stats-one-line
    echo "[s3] Ready: $S3_LOCAL_FILE"

elif [ "$S3_FILE_ACTION" = "removed" ]; then
    echo "[s3] Delete event — no file to download."

else
    echo "[s3] Unhandled event type '$S3_EVENT_TYPE'."
fi

export S3_LOCAL_FILE
unset _s3_json _s3_key _s3_path _s3_tmp_dir _s3_filename _s3_new_parent _s3_new_name
