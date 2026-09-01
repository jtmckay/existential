#!/usr/bin/env bash
# Host-side setup for 10-minio-file-processing, run by e2e.sh's stage_checks
# before the stack boots.
#
# Only two things live here, and both for the same reason: they are read once at
# container start, so nothing running inside the daemon can change them. Anything
# that can wait until the check itself runs belongs in the routine, where MinIO's
# credentials actually exist — the rclone remote is written there for exactly
# that reason.
#
# Contract: $WORK is the e2e clone. Exit non-zero to fail the run. Every write
# lands inside the clone and is torn down with it.
set -euo pipefail

WORK="${WORK:?}"
BUCKET="e2e-flow"

grep -q '^EXIST_IS_NAS_MINIO=true' "$WORK/.env.shared" || exit 0
WCFG="$WORK/services/decree/webhook/config.exist.yml"
[ -f "$WCFG" ] || exit 0

# ── The probe processor ──────────────────────────────────────────────────────
#
# Matches only this run's bucket and needs no model: CRITERIA is deliberately
# empty, because the natural-language gate costs a model call and this is about
# wiring, not judgment.
#
# It ASSERTS ITS OWN INPUTS and exits non-zero when they are wrong. That is what
# makes the chain testable at all — decree runs one message at a time and the
# check IS that message, so no check can ever wait for the processor it
# triggers. The processor has to be the thing that fails, and e2e's
# every-run-is-graded rule turns that failure into a red row.
mkdir -p "$WORK/automations/lib/file-processors"
cat > "$WORK/automations/lib/file-processors/e2e-probe.sh" << PROC
#!/usr/bin/env bash
# shellcheck disable=SC2034  # PATTERN/CRITERIA are read by file-processor, not set by it
PATTERN="nextcloud:${BUCKET}/.*\.txt"
CRITERIA=""
IS_PRE_SIGNED=false
set -euo pipefail
[ "\${FILE_ACTION:-}" = "removed" ] && { echo "E2E-PROBE removed \${FILE_KEY}"; exit 0; }
echo "E2E-PROBE-SOURCE \${FILE_SOURCE}"
[ -s "\$FILE_PATH" ] || { echo "E2E-PROBE-FAIL empty or missing \${FILE_PATH}" >&2; exit 1; }
# The object's body is the token in its own name; if those disagree the router
# handed the processor the wrong file.
_want="\${FILE_KEY##*/}"; _want="\${_want#probe-}"; _want="\${_want%.txt}"
_got="\$(cat "\$FILE_PATH")"
[ "\$_got" = "\$_want" ] || { echo "E2E-PROBE-FAIL want \${_want} got \${_got}" >&2; exit 1; }
echo "E2E-PROBE-OK \${_got}"
PROC

# ── The webhook's rclone_prefix ──────────────────────────────────────────────
#
# minio-router DROPS the S3 bucket when it builds FILE_SOURCE — it emits
# "<rclone_src>:<rclone_prefix>/<key>". That is right for the topology it was
# written for, where the bucket IS a nextcloud external mount and the
# nextcloud-side path is the prefix. This check talks to MinIO directly through
# an s3 remote, where the first path segment must be the bucket — so the prefix
# is where the bucket has to go.
awk -v b="$BUCKET" '
    /^  - path: \/minio$/ { inblock = 1 }
    inblock && /^      rclone_prefix:/ { print "      rclone_prefix: " b; inblock = 0; next }
    { print }
' "$WCFG" > "${WCFG}.tmp" && mv "${WCFG}.tmp" "$WCFG"
grep -q "rclone_prefix: ${BUCKET}" "$WCFG" || { echo "could not set rclone_prefix" >&2; exit 1; }

echo "  staged MinIO probe processor + rclone_prefix=${BUCKET}"
