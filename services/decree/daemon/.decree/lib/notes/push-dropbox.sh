#!/usr/bin/env bash
# Sync Dropbox
#
# Syncs compiled output to Dropbox via rclone.
# Skips sync if the output volume is empty.
set -euo pipefail

message_file="${message_file:-}"
message_id="${message_id:-}"
message_dir="${message_dir:-}"
chain="${chain:-}"
seq="${seq:-}"

if [ "${DECREE_PRE_CHECK:-}" = "true" ]; then
    command -v rclone >/dev/null 2>&1 || { echo "rclone not found" >&2; exit 1; }
    exit 0
fi

# Check if output directory has content before syncing
count=$(find /dropbox_data -maxdepth 1 -type f | wc -l)
if [ "$count" -gt 0 ]; then
    rclone sync --config /secrets/rclone/rclone.conf \
        --exclude ".sync_*" \
        --exclude ".compile-*" \
        /dropbox_data "dropbox:${DROPBOX_DEST_DIR}"
else
    echo "Output volume is empty, skipping sync."
fi
