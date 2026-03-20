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
    command -v docker >/dev/null 2>&1 || { echo "docker not found" >&2; exit 1; }
    exit 0
fi

# Check if volume has content before syncing
count=$(docker compose --profile worker run --rm --entrypoint ls decree-dropbox /data 2>/dev/null | wc -l)
if [ "$count" -gt 0 ]; then
    docker compose --profile worker run --rm decree-dropbox
else
    echo "Output volume is empty, skipping sync."
fi
