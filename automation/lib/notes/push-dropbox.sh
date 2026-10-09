#!/usr/bin/env bash
# Sync Dropbox
#
# Syncs compiled output to Dropbox via rclone.
# Skips sync if the output volume is empty.
set -euo pipefail

# Check if output directory has content before syncing
count=$(find /data/dropbox -maxdepth 1 -type f 2>/dev/null | wc -l)
if [ "$count" -gt 0 ]; then
    rclone sync --config /secrets/rclone/rclone.conf \
        --exclude ".sync_*" \
        --exclude ".compile-*" \
        /data/dropbox "dropbox:${DROPBOX_DEST_DIR}"
else
    echo "Output volume is empty, skipping sync."
fi
