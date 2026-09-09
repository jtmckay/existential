#!/usr/bin/env bash
# e2e-s3-file-processing — the object store → webhook → router → processor chain.
#
# Staged into the clone's shared_routines/ by e2e.sh and triggered by the
# migration in 90-s3-file-processing.md. Runs inside decree, so it reaches
# seaweedfs over the exist bridge with rclone and reads the rendered stack at
# /repo. Every write lands in the disposable e2e clone.
#
# Setup that must happen before the daemon boots (the probe processor, the
# webhook's rclone_prefix, and the notification path_prefixes) is done on the
# host in e2e.sh's stage_checks — all three are read once at container start, so
# nothing running inside can change them.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ "${DECREE_PRE_CHECK:-}" = "true" ]; then
    # shellcheck source=../../../../automation/lib/precheck.sh
    source "${SCRIPT_DIR}/../lib/precheck.sh"
    command -v rclone >/dev/null 2>&1 || precheck_fail "e2e-s3-file-processing" "rclone not found"
    [ -n "${S3_ACCESS_KEY:-}" ] || precheck_fail "e2e-s3-file-processing" "S3_ACCESS_KEY not set"
    precheck_pass "e2e-s3-file-processing"
    exit 0
fi

REPO="${E2E_REPO:-/repo}"
INBOX="${E2E_INBOX:-/work/.decree/inbox}"
RUNS="${E2E_RUNS:-/work/.decree/runs}"
S3_URL="${S3_URL:-http://seaweedfs:8333}"
BUCKET="${E2E_BUCKET:-e2e-flow}"
TOKEN="e2eprobe$(date +%s%N)"
OBJECT="probe-${TOKEN}.txt"

say()  { printf '  %s\n' "$*"; }
fail() { printf '  FAIL  %s\n' "$*" >&2; exit 1; }

# Poll until a command succeeds. Cheaper and far less flaky than a fixed sleep.
until_ok() {
    local what="$1" timeout="$2"; shift 2
    local deadline=$(( SECONDS + timeout ))
    while [ "$SECONDS" -lt "$deadline" ]; do
        if "$@" >/dev/null 2>&1; then say "ok    ${what}"; return 0; fi
        sleep 2
    done
    printf '  FAIL  %s — not observed within %ss\n' "$what" "$timeout" >&2
    return 1
}

# ── 1. The configured webhook endpoint is actually served ────────────────────
#
# The bug this exists for is a wrong PORT in the notify config, so the endpoint
# has to be READ from the rendered config rather than assumed. Under minIO that
# config was compose env; under seaweedfs it is notification.toml, but the
# property being asserted is identical. Probing from decree tests the same thing
# — both sit on the one exist bridge, so a port nothing serves is unreachable
# from either — and needs no docker socket.
NOTIFY="${REPO}/nas/seaweedfs/notification.toml"
[ -f "$NOTIFY" ] || fail "no rendered notification config at ${NOTIFY}"
ENDPOINT=$(grep -m1 '^endpoint[[:space:]]*=' "$NOTIFY" | cut -d'"' -f2 || true)
[ -n "$ENDPOINT" ] || fail "no endpoint found in ${NOTIFY}"
say "seaweedfs is configured to post to ${ENDPOINT}"

HEALTH="${ENDPOINT%/s3}/healthz"
curl -sf --max-time 5 -o /dev/null "$HEALTH" \
    || fail "${HEALTH} is not served — the notify endpoint points at a dead port"
say "ok    ${HEALTH} reachable"

# ── 2. The rclone remote file-processor downloads through ───────────────────
#
# Written here rather than staged on the host because it is read at routine
# runtime, not at boot — and because the credentials only exist once the
# templates have rendered, which is after staging. /secrets is decree's one
# read-write mount and /secrets/rclone/rclone.conf is the path file-processor
# hardcodes. Named "nextcloud" because that is what the webhook's /s3 route
# calls the remote.
mkdir -p /secrets/rclone
cat > /secrets/rclone/rclone.conf << CONF
[nextcloud]
type = s3
provider = Other
env_auth = false
access_key_id = ${S3_ACCESS_KEY}
secret_access_key = ${S3_SECRET_KEY}
endpoint = ${S3_URL}
region = us-east-1
force_path_style = true
CONF
say "wrote rclone remote 'nextcloud' → ${S3_URL}"

# ── 3. The bucket ────────────────────────────────────────────────────────────
#
# No subscription step, and that is the point: seaweedfs has no
# PutBucketNotificationConfiguration, so the webhook is declared once in
# notification.toml and read at boot. stage_checks adds this bucket to that
# file's path_prefixes; there is nothing to turn on from in here.
export RCLONE_CONFIG=/secrets/rclone/rclone.conf
rclone mkdir "nextcloud:${BUCKET}" >/dev/null 2>&1 || true
rclone lsd "nextcloud:${BUCKET}" >/dev/null 2>&1 \
    || fail "could not create or reach bucket ${BUCKET} at ${S3_URL}"
say "bucket ${BUCKET} ready (watched via notification.toml path_prefixes)"

# ── 4. Drop the file in. Everything after this is observation ────────────────
printf '%s' "$TOKEN" > "/tmp/${OBJECT}"
rclone copyto "/tmp/${OBJECT}" "nextcloud:${BUCKET}/${OBJECT}" >/dev/null \
    || fail "could not upload ${OBJECT}"
rm -f "/tmp/${OBJECT}"
say "uploaded ${BUCKET}/${OBJECT}"

# ── 5. The event reaches decree ──────────────────────────────────────────────
#
# This is where the assertion stops, and the reason is structural: decree runs
# ONE message at a time, and this check is the message it is running. The
# s3-router message the upload produces is queued BEHIND this routine and
# cannot start until it returns — so no amount of waiting here will ever see the
# processor run.
#
# What is left to prove is therefore graded elsewhere, by properties that cost
# no new mechanism:
#
#   the event arrived            asserted here — an s3-router message is in
#                                the inbox. This is the bug the whole check
#                                exists for: a wrong port means nothing arrives.
#   the router matched it, and
#   the processor read the file  the example processor staged as the probe
#                                asserts its download is non-empty and exits
#                                non-zero otherwise, so a break dead-letters
#                                that message.
#   nothing broke                every run in the clone is graded, so the
#                                router's and the processor's own runs each get
#                                a row of their own.
#
# The budget is generous because it waits on a QUEUE and on the object store's
# own notify retry, not on the pipeline; measured, the webhook enqueues in well
# under a second once seaweedfs has fired.
# Look in the INBOX, not in runs/. A run directory is created when decree starts
# processing a message, and decree runs one message at a time — this check IS the
# message it is running, so the router's run dir cannot exist yet by construction.
# Watching runs/ here waits out the full timeout on a chain that is working.
#
# And match the routine KEY, not a bare "s3-router": that string also appears
# in this check's own message.md, in its needs_routines, so a loose grep reported
# success before anything had been sent at all.
_router_queued() {
    grep -lq '^routine: s3-router' "$INBOX"/*.md 2>/dev/null \
        || grep -rlq '^routine: s3-router' "$RUNS"/*/message.md 2>/dev/null
}
until_ok "seaweedfs event reached decree as an s3-router message" 180 _router_queued \
    || fail "the webhook never enqueued anything — seaweedfs posted, but nothing arrived"

say "chain wired; s3-router is queued behind this check"
say "probe object: ${BUCKET}/${OBJECT}"
