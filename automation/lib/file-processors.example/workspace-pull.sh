#!/usr/bin/env bash
# shellcheck disable=SC2034  # PATTERN/CRITERIA/IS_PRE_SIGNED are read out of this
# file's source by minio-router and file-processor, not by sourcing it.
# Workspace pull — the live half of workspace-sync's MinIO -> local direction.
#
# workspace-sync (cron, every 10 min by default) covers local -> MinIO by
# design: nothing fires when you edit the bind mount by hand, so it has to
# poll. MinIO -> local doesn't need to poll — MinIO already tells decree about
# every object change the moment it happens, via the webhook the nextcloud
# bucket is subscribed to. This processor acts on that for the workspace/
# subtree: it downloads the changed object straight to its place in
# workspace/ (or deletes it locally on a removed event), so a MinIO- or
# Nextcloud-side edit shows up in workspace/ within about a second instead of
# waiting for the next cron tick.
#
# Deliberately a plain copy, not a call into workspace-sync's bisync: running
# bisync per-event would serialize every workspace edit through decree's
# one-message-at-a-time queue and fight the cron run's own state cache. The
# cron run still happens on schedule and reconciles anything this missed (a
# burst of events during an outage, for instance) — this is a latency
# shortcut for the common case, not a replacement for the sync.
#
# Copy to lib/file-processors/ to activate — no restart needed, minio-router
# reads the directory per event. Needs workspace-sync's cron already active
# (services/automation/backup/cron.example/workspace-sync.md) and the
# nextcloud bucket subscribed to the webhook — see that routine's own header
# for the exact FIRST RUN order (sync once before subscribing).
PATTERN="^nextcloud:S3/workspace/"
CRITERIA=""
IS_PRE_SIGNED=false

set -euo pipefail

WORKSPACE_DIR="${WORKSPACE_DIR:-/workspace}"
# Mirrors workspace-sync's own default — keep them in step if you change either.
WORKSPACE_S3_PREFIX="${WORKSPACE_S3_PREFIX:-workspace}"

# FILE_KEY is "S3/workspace/<path>" — S3 is Nextcloud's external-storage mount
# point for this bucket, workspace/ is the synced subfolder within it.
_rel="${FILE_KEY#S3/${WORKSPACE_S3_PREFIX}/}"
_target="${WORKSPACE_DIR}/${_rel}"

if [ "$FILE_ACTION" = "removed" ]; then
    rm -f -- "$_target"
    echo "Removed locally: ${_rel}"
    exit 0
fi

mkdir -p -- "$(dirname -- "$_target")"
# -p carries over FILE_PATH's modtime, which file-processor's rclone copyto
# already set to match the MinIO object's — matching modtimes on both sides is
# what lets the next bisync run see this as already in sync rather than a
# same-name file that changed on both sides since its last look.
cp -p -- "$FILE_PATH" "$_target"
echo "Pulled live: ${_rel}"
