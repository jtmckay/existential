#!/usr/bin/env bash
# MinIO Router
#
# Receives minIO S3 webhook events, matches the full FILE_SOURCE path against
# every processor in lib/file-processors/, and enqueues one file-processor
# message per match. The file is downloaded per-processor — no shared state.
#
# Example webhook trigger (fired by /minio endpoint):
#
#   ---
#   routine: minio-router
#   rclone_src: nextcloud
#   rclone_prefix: S3
#   ---
#   {"EventName":"s3:ObjectCreated:Put","Key":"mybucket/path/to/file.pdf","Records":[...]}
set -euo pipefail

message_file="${message_file:-}"
message_id="${message_id:-}"
message_dir="${message_dir:-}"
chain="${chain:-}"
seq="${seq:-}"

if [ "${DECREE_PRE_CHECK:-}" = "true" ]; then
    # shellcheck source=../lib/precheck.sh
    source "$(dirname "${BASH_SOURCE[0]}")/../lib/precheck.sh"
    command -v jq >/dev/null 2>&1 || precheck_fail "minio-router" "jq not found"
    precheck_pass "minio-router"
    exit 0
fi

rclone_src="${rclone_src:-nextcloud}"
rclone_prefix="${rclone_prefix:-}"

# Parse the event
_json=$(awk 'NR==1 && /^---$/{skip=1; next} skip && /^---$/{skip=0; next} !skip' \
    "$message_file" | sed '/./,$!d')

if [ -z "$_json" ]; then
    echo "Empty message body, nothing to route."
    exit 0
fi

_event_name=$(echo "$_json" | jq -r '.EventName // empty')
_key=$(echo "$_json"        | jq -r '.Key        // empty')

if [ -z "$_event_name" ] || [ -z "$_key" ]; then
    echo "Could not parse EventName or Key — verify minIO is sending S3-compatible events."
    echo "Payload: $_json"
    exit 1
fi

_bucket="${_key%%/*}"
_object_key="${_key#*/}"
_prefix="${rclone_prefix:+${rclone_prefix%/}/}"
_file_source="${rclone_src}:${_prefix}${_object_key}"

# Translate S3 event name to a clean action string
if [[ "$_event_name" == *"ObjectCreated"* ]]; then
    _file_action="created"
elif [[ "$_event_name" == *"ObjectRemoved"* ]]; then
    _file_action="removed"
else
    echo "Unhandled event type '$_event_name' — skipping."
    exit 0
fi

echo "Event:  $_event_name → $_file_action"
echo "Source: $_file_source"

# Find all matching processors and enqueue a file-processor message for each
_processors_dir="$(dirname "${BASH_SOURCE[0]}")/../lib/file-processors"
_matched=0

for _processor in "$_processors_dir"/*.sh; do
    [ -f "$_processor" ] || continue
    _raw=$(grep -m1 '^PATTERN=' "$_processor" || true)
    _pattern=$(echo "$_raw" | sed "s/^PATTERN=[\"']\(.*\)[\"']$/\1/")
    [ -z "$_pattern" ] && continue

    if [[ "$_file_source" =~ $_pattern ]]; then
        _processor_name=$(basename "$_processor" .sh)
        _outbox_file="/work/.decree/outbox/${message_id}-${_processor_name}.md"

        cat > "$_outbox_file" << EOF
---
routine: file-processor
rclone_path: ${_file_source}
processor: ${_processor_name}
file_action: ${_file_action}
---
EOF
        echo "Queued: $_processor_name"
        _matched=$((_matched + 1))
    fi
done

if [ "$_matched" -eq 0 ]; then
    echo "No processors matched '$_file_source'."
else
    echo "Routed to $_matched processor(s)."
fi
