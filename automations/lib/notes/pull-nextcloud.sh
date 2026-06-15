#!/usr/bin/env bash
# Sync Nextcloud
#
# Syncs notes from Nextcloud to the local notes cache at /data/notes.
# Requires DECREE_NOTES_DIR to be set (e.g. "S3/Notes") and a configured
# "nextcloud:" rclone remote at /secrets/rclone/rclone.conf.
set -euo pipefail

if [ "${DECREE_PRE_CHECK:-}" = "true" ]; then
    command -v rclone >/dev/null 2>&1 || { echo "rclone not found" >&2; exit 1; }
    [ -n "${DECREE_NOTES_DIR:-}" ]    || { echo "DECREE_NOTES_DIR not set" >&2; exit 1; }
    [ -f /secrets/rclone/rclone.conf ] || { echo "rclone.conf not found at /secrets/rclone/rclone.conf" >&2; exit 1; }
    rclone listremotes --config /secrets/rclone/rclone.conf | grep -q '^nextcloud:' \
        || { echo "rclone remote 'nextcloud:' not configured" >&2; exit 1; }
    exit 0
fi

: "${DECREE_NOTES_DIR:?DECREE_NOTES_DIR is not set — add it to the notes cron frontmatter or compose env}"

echo "Syncing nextcloud:${DECREE_NOTES_DIR} -> /data/notes"

mkdir -p /data/notes
touch /data/notes/.write-test 2>/dev/null \
    || { echo "ERROR: /data/notes is not writable — check volume mount and ownership" >&2; exit 1; }
rm -f /data/notes/.write-test

before=$(find /data/notes -type f -not -name '.write-test' | wc -l)
rclone sync --config /secrets/rclone/rclone.conf \
    --stats-one-line --stats 0 \
    "nextcloud:${DECREE_NOTES_DIR}" /data/notes
after=$(find /data/notes -type f | wc -l)
echo "Sync complete: ${after} file(s) (was ${before})"
