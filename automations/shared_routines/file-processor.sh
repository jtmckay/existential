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
#   is_pre_signed: false
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
is_pre_signed="${is_pre_signed:-false}"

if [ -z "$rclone_path" ]; then
    echo "rclone_path is required."
    exit 1
fi
if [ -z "$processor" ]; then
    echo "processor is required."
    exit 1
fi

# SEC-12: `processor` and `rclone_path` arrive via message frontmatter, which can
# originate from untrusted input (minio-router enqueues these from S3 events whose
# object keys an attacker may control). Validate before use.
#
# `processor` is interpolated into the script path below — constrain it to a bare
# slug so it can never traverse out of lib/file-processors/ (no `/`, no `..`, no
# command substitution survives this).
if ! [[ "$processor" =~ ^[A-Za-z0-9._-]+$ ]]; then
    echo "Invalid processor name '$processor' (allowed: letters, digits, . _ -)." >&2
    exit 1
fi
# Reject control characters in the rclone path. It is always quoted when passed to
# rclone (no command injection), but a newline here is a strong injection signal.
# (has_control_chars uses tr|wc, not grep, which would miss a newline.)
source "$(dirname "${BASH_SOURCE[0]}")/../lib/validate.sh"
if has_control_chars "$rclone_path"; then
    echo "Invalid rclone_path (contains control characters)." >&2
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
export PRE_SIGNED_URL=""

_tmpfile=""
trap '[ -n "$_tmpfile" ] && rm -f "$_tmpfile" && echo "Deleted: $_tmpfile"' EXIT

if [ "$file_action" = "created" ]; then
    if [ "$is_pre_signed" = "true" ]; then
        echo "Generating signed URL for $rclone_path"
        _signed_url=$(rclone link "$rclone_path" \
            --config /secrets/rclone/rclone.conf)
        export PRE_SIGNED_URL="$_signed_url"
        echo "Signed URL: $PRE_SIGNED_URL"
    else
        _filename=$(basename "$_file_key")
        _tmpfile=$(mktemp "${message_dir:-/work/.decree/runs}/${_filename}.XXXXXX")

        echo "Downloading $rclone_path → $_tmpfile"
        rclone copyto "$rclone_path" "$_tmpfile" \
            --config /secrets/rclone/rclone.conf \
            --progress \
            --stats-one-line

        export FILE_PATH="$_tmpfile"
    fi
fi

# SEC-12: processors parse untrusted file bytes (and OCR/transcribe call out to
# long-running services). Bound execution so a malformed/malicious file can't hang
# the routine indefinitely. The default is generous so legitimate large
# transcriptions still finish; override FILE_PROCESSOR_TIMEOUT (seconds) via env or
# frontmatter for cheap processors, or set it to 0 to disable the bound.
_timeout="${FILE_PROCESSOR_TIMEOUT:-1800}"
echo "Running processor: $processor (action: $file_action, timeout: ${_timeout}s)"
if [ "$_timeout" = "0" ]; then
    bash "$_processor_script"
else
    timeout --signal=TERM "$_timeout" bash "$_processor_script"
fi
