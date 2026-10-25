#!/usr/bin/env bash
# Host-side setup for 10-file-processing, run by e2e.sh's stage_checks before
# the stack boots.
#
# lib/ is mounted read-only into the daemon, so the probe processor has to be
# placed from out here. So do the webhook registration and rclone remote
# migrations, the nextcloud-capture flow's, so any unit with Nextcloud on boots
# with file events whether or not it turned that flow on.
#
# Contract: $WORK is the e2e clone. Exit non-zero to fail the run. Every write
# lands inside the clone and is torn down with it.
set -euo pipefail

WORK="${WORK:?}"

grep -q '^EXIST_IS_NAS_NEXTCLOUD=true' "$WORK/.env.shared" || exit 0

# The SHIPPED example is the probe. It already matches `nextcloud:.*\.txt` with
# an empty CRITERIA — no model call, which is right for a wiring test — and
# since it asserts its own downloaded file is non-empty, a break anywhere in the
# chain exits non-zero and e2e's every-run-is-graded rule turns that into a red
# row.
mkdir -p "$WORK/automation/lib/file-processors"
cp "$WORK/automation/lib/file-processors.example/example.sh" \
   "$WORK/automation/lib/file-processors/"

echo "  staged the example file-processor as the probe"

mkdir -p "$WORK/volumes/workspace_data/.decree/migrations"
for _m in 23-nextcloud-rclone-remote.md 27-nextcloud-file-events.md; do
    cp -n "$WORK/flows/nextcloud-capture/migrations/$_m" "$WORK/volumes/workspace_data/.decree/migrations/"
done
echo "  staged the nextcloud migrations (rclone remote, file events)"
