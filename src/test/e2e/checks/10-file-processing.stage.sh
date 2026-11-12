#!/usr/bin/env bash
# Host-side setup for 10-file-processing, run by e2e.sh's stage_checks before
# the stack boots.
#
# The probe processor is placed in the workspace's decree lib from out here, before
# the stack boots, and nextcloud-capture is turned on, so any unit with Nextcloud
# on boots with file events whether or not it turned that flow on.
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
# It ships in the file_processor plugin's lib, so it is read out of that file the
# way test lint does (awk: this is the host).
_dst="$WORK/volumes/workspace_data/.decree/lib/file-processors"
mkdir -p "$_dst"
awk '/^lib:/{l=1; next} /^[A-Za-z_-]/{l=0} l && /^  file-processors\.example\/example\.sh: [|][-+]?$/{f=1; next}
     f && /^  [^ ]/{exit} f {print (length($0) >= 4 ? substr($0, 5) : "")}' \
    "$WORK/automation/plugins/file_processor.md" > "$_dst/example.sh"
[ -s "$_dst/example.sh" ] || { echo "  no example processor in automation/plugins/file_processor.md" >&2; exit 1; }

echo "  staged the example file-processor as the probe"

# nextcloud-capture on in the workspace's plugins.yml: exist.initial.sh then
# installs its plugins and queues their migrations (rclone remote, file events).
# shellcheck source=../../../utils/flows.sh
# shellcheck disable=SC2034  # REPO_DIR is read by flows.sh
( REPO_DIR="$WORK"; . "$WORK/src/utils/flows.sh"; plugins_turn on nextcloud-capture )
echo "  turned on nextcloud-capture (rclone remote, file events)"
