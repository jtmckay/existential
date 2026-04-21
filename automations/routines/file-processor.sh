#!/usr/bin/env bash
# File Processor
#
# Downloads a file from any rclone remote, passes it to the named processor
# in lib/file-processors/, then explicitly deletes the temp file.
# Not minIO-specific — works with any rclone path.
#
# Enqueued by minio-router; not typically triggered directly.
#
#   ---
#   routine: file-processor
#   rclone_path: minio:mybucket/path/to/file.pdf
#   processor: my-processor
#   file_action: created
#   ---
set -euo pipefail

message_file="${message_file:-}"
message_id="${message_id:-}"
message_dir="${message_dir:-}"
chain="${chain:-}"
seq="${seq:-}"

if [ "${DECREE_PRE_CHECK:-}" = "true" ]; then
    # shellcheck source=../lib/precheck.sh
    source "$(dirname "${BASH_SOURCE[0]}")/../lib/precheck.sh"
    command -v rclone >/dev/null 2>&1 || precheck_fail "file-processor" "rclone not found"
    precheck_pass "file-processor"
    exit 0
fi

rclone_path="${rclone_path:-}"
processor="${processor:-}"
file_action="${file_action:-created}"

if [ -z "$rclone_path" ]; then
    echo "rclone_path is required."
    exit 1
fi
if [ -z "$processor" ]; then
    echo "processor is required."
    exit 1
fi

_processor_script="$(dirname "${BASH_SOURCE[0]}")/../lib/file-processors/${processor}.sh"
if [ ! -f "$_processor_script" ]; then
    echo "Processor not found: $_processor_script"
    exit 1
fi

# Derive a clean key from the rclone path (strip "remote:" prefix)
_file_key="${rclone_path#*:}"

export FILE_SOURCE="$rclone_path"
export FILE_KEY="$_file_key"
export FILE_ACTION="$file_action"
export FILE_PATH=""

_tmpfile=""
trap '[ -n "$_tmpfile" ] && rm -f "$_tmpfile" && echo "Deleted: $_tmpfile"' EXIT

if [ "$file_action" = "created" ]; then
    _filename=$(basename "$_file_key")
    _tmpfile=$(mktemp "/tmp/${_filename}.XXXXXX")

    echo "Downloading $rclone_path → $_tmpfile"
    rclone copyto "$rclone_path" "$_tmpfile" \
        --config /secrets/rclone/rclone.conf \
        --progress \
        --stats-one-line

    export FILE_PATH="$_tmpfile"
fi

echo "Running processor: $processor (action: $file_action)"
bash "$_processor_script"
