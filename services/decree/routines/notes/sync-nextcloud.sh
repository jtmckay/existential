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
    command -v docker >/dev/null 2>&1 || { echo "docker not found" >&2; exit 1; }
    exit 0
fi

docker compose --profile worker run --rm decree-notes
