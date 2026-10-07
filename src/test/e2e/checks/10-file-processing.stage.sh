#!/usr/bin/env bash
# Host-side setup for 10-file-processing, run by e2e.sh's stage_checks before
# the stack boots.
#
# lib/ is mounted read-only into the daemon, so the probe processor has to be
# placed from out here. Everything else the check needs — the webhook
# registration, the rclone remote — is done by the Core quest's migrations.
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
