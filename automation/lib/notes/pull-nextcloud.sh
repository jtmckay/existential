#!/usr/bin/env bash
# Sync Nextcloud
#
# Syncs notes from Nextcloud to the local notes cache at /data/notes.
# Requires NOTES_REMOTE_DIR to be set (e.g. "Notes") and a configured
# "nextcloud:" rclone remote at /secrets/rclone/rclone.conf.
set -euo pipefail

[ -f /secrets/rclone/rclone.conf ] || { echo "rclone.conf not found at /secrets/rclone/rclone.conf — run the nextcloud_rclone_remote migration" >&2; exit 1; }
: "${NOTES_REMOTE_DIR:?NOTES_REMOTE_DIR is not set — AUTOMATION_NOTES_DIR in services/automation/.env}"

echo "Syncing nextcloud:${NOTES_REMOTE_DIR} -> /data/notes"

mkdir -p /data/notes
touch /data/notes/.write-test 2>/dev/null \
    || { echo "ERROR: /data/notes is not writable — check volume mount and ownership" >&2; exit 1; }
rm -f /data/notes/.write-test

before=$(find /data/notes -type f -not -name '.write-test' | wc -l)
rclone sync --config /secrets/rclone/rclone.conf \
    --stats-one-line --stats 0 \
    "nextcloud:${NOTES_REMOTE_DIR}" /data/notes
after=$(find /data/notes -type f | wc -l)
echo "Sync complete: ${after} file(s) (was ${before})"
