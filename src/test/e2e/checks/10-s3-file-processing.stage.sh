#!/usr/bin/env bash
# Host-side setup for 90-s3-file-processing, run by e2e.sh's stage_checks
# before the stack boots.
#
# Only three things live here, and all for the same reason: they are read once at
# container start, so nothing running inside the daemon can change them. Anything
# that can wait until the check itself runs belongs in the routine, where the
# object store's credentials actually exist — the rclone remote is written there
# for exactly that reason.
#
# Contract: $WORK is the e2e clone. Exit non-zero to fail the run. Every write
# lands inside the clone and is torn down with it.
set -euo pipefail

WORK="${WORK:?}"
BUCKET="e2e-flow"

grep -q '^EXIST_IS_NAS_SEAWEEDFS=true' "$WORK/.env.shared" || exit 0
WCFG="$WORK/services/automation/webhook/config.exist.yml"
[ -f "$WCFG" ] || exit 0

# ── The probe processor ──────────────────────────────────────────────────────
#
# The SHIPPED example is the probe. It already matches `nextcloud:.*\.txt` with
# an empty CRITERIA — no model call, which is right for a wiring test — and
# since it asserts its own downloaded file is non-empty, a break anywhere in the
# chain exits non-zero and e2e's every-run-is-graded rule turns that into a red
# row. That assertion is the only thing this check needs a processor to do, and
# a generated near-copy of the example was 17 lines of drift waiting to happen.
mkdir -p "$WORK/automation/lib/file-processors"
cp "$WORK/automation/lib/file-processors.example/example.sh" \
   "$WORK/automation/lib/file-processors/"

# ── The webhook's rclone_prefix ──────────────────────────────────────────────
#
# s3-router DROPS the bucket when it builds FILE_SOURCE — it emits
# "<rclone_src>:<rclone_prefix>/<key>". That is right for the topology it was
# written for, where the bucket IS a nextcloud external mount and the
# nextcloud-side path is the prefix. This check talks to the object store
# directly through an s3 remote, where the first path segment must be the bucket
# — so the prefix is where the bucket has to go.
awk -v b="$BUCKET" '
    /^  - path: \/s3$/ { inblock = 1 }
    inblock && /^      rclone_prefix:/ { print "      rclone_prefix: " b; inblock = 0; next }
    { print }
' "$WCFG" > "${WCFG}.tmp" && mv "${WCFG}.tmp" "$WCFG"
grep -q "rclone_prefix: ${BUCKET}" "$WCFG" || { echo "could not set rclone_prefix" >&2; exit 1; }

# ── The notification path_prefixes ───────────────────────────────────────────
#
# New under seaweedfs and load-bearing. minIO subscribed per bucket at runtime,
# so a test bucket could opt itself in with one `mc event add`. Seaweedfs filters
# by FILER PATH in a file read at boot, and the shipped value watches only
# /buckets/nextcloud — so without this line the probe bucket fires no events at
# all and the check fails on a chain that is perfectly healthy.
NCFG="$WORK/nas/seaweedfs/notification.exist.toml"
[ -f "$NCFG" ] || { echo "no ${NCFG}" >&2; exit 1; }
sed -i "s|^path_prefixes = \[\"/buckets/nextcloud\"\]$|path_prefixes = [\"/buckets/nextcloud\", \"/buckets/${BUCKET}\"]|" "$NCFG"
grep -q "/buckets/${BUCKET}" "$NCFG" || { echo "could not add ${BUCKET} to path_prefixes" >&2; exit 1; }

echo "  staged the example file-processor + rclone_prefix=${BUCKET} + path_prefixes"
