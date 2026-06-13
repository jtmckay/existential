#!/usr/bin/env bash
# openviking-sync — rclone sync from a remote into a local directory, then
# trigger OpenViking to re-index any changed files via the watches API.
#
# Env vars (set via cron frontmatter):
#   SYNC_REMOTE  rclone remote + path (e.g. "nextcloud:/Obsidian")
#   SYNC_DEST    local destination dir inside the sidecar (e.g. /notes, /resources)
#
# Env vars (passed through sidecar compose env):
#   OPENVIKING_API_KEY  Bearer token for the OpenViking REST API
set -euo pipefail

if [[ "${DECREE_PRE_CHECK:-}" == "true" ]]; then
    command -v rclone >/dev/null 2>&1 || { echo "rclone not found" >&2; exit 1; }
    command -v curl   >/dev/null 2>&1 || { echo "curl not found" >&2; exit 1; }
    [[ -n "${SYNC_REMOTE:-}" ]]        || { echo "SYNC_REMOTE not set in frontmatter" >&2; exit 1; }
    [[ -n "${SYNC_DEST:-}" ]]          || { echo "SYNC_DEST not set in frontmatter" >&2; exit 1; }
    [[ -f /secrets/rclone/rclone.conf ]] || { echo "/secrets/rclone/rclone.conf not found" >&2; exit 1; }
    [[ -n "${OPENVIKING_API_KEY:-}" ]] || { echo "OPENVIKING_API_KEY not set" >&2; exit 1; }
    exit 0
fi

OPENVIKING_URL="${OPENVIKING_URL:-http://openviking:1933}"

echo "Syncing ${SYNC_REMOTE} → ${SYNC_DEST}"
rclone sync --config /secrets/rclone/rclone.conf "${SYNC_REMOTE}" "${SYNC_DEST}"
echo "Sync complete"

# Trigger a refresh on any active watches. If no watches exist yet this is a
# no-op — run the 01-watch-dirs migration first.
WATCHES=$(curl -fsS --max-time 10 \
    -H "Authorization: Bearer ${OPENVIKING_API_KEY}" \
    "${OPENVIKING_URL}/api/v1/watches" 2>/dev/null || echo "{}")

echo "${WATCHES}" | grep -o '"task_id":"[^"]*"' | sed 's/"task_id":"//;s/"//' | while read -r task_id; do
    echo "Triggering watch refresh: ${task_id}"
    curl -fsS -X POST --max-time 30 \
        -H "Authorization: Bearer ${OPENVIKING_API_KEY}" \
        "${OPENVIKING_URL}/api/v1/watches/${task_id}/trigger" >/dev/null \
        && echo "  refreshed ${task_id}" \
        || echo "  refresh failed for ${task_id} (non-fatal)" >&2
done

echo "OpenViking sync complete"
