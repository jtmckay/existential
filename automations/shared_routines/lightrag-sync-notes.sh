#!/usr/bin/env bash
# lightrag-sync-notes — rclone sync from remote into /notes (lightrag inputs).
#
# Required env var (set in cron frontmatter):
#   LIGHTRAG_NOTES_REMOTE  rclone remote + path, e.g. "nextcloud:/Obsidian"
set -euo pipefail

if [[ "${DECREE_PRE_CHECK:-}" == "true" ]]; then
    command -v rclone >/dev/null 2>&1 || { echo "rclone not found" >&2; exit 1; }
    [[ -n "${LIGHTRAG_NOTES_REMOTE:-}" ]] || { echo "LIGHTRAG_NOTES_REMOTE not set" >&2; exit 1; }
    [[ -f /secrets/rclone/rclone.conf ]] || { echo "/secrets/rclone/rclone.conf not found" >&2; exit 1; }
    exit 0
fi

echo "Syncing ${LIGHTRAG_NOTES_REMOTE} → /notes"
rclone sync --config /secrets/rclone/rclone.conf "${LIGHTRAG_NOTES_REMOTE}" /notes
echo "Sync complete"
