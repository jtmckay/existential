#!/usr/bin/env bash
# Sync Nextcloud
#
# Syncs notes from Nextcloud to the local notes volume via rclone.
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

rclone sync --config /config/rclone/rclone.conf "nextcloud:${DECREE_NOTES_DIR}" /notes_data
