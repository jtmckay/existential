#!/usr/bin/env bash
# e2e-minio-file-processing — the MinIO → webhook → router → processor chain.
#
# Staged into the clone's shared_routines/ by e2e.sh and triggered by the
# migration in 90-minio-file-processing.md. Runs inside decree, so it reaches
# MinIO over the exist bridge with mc and reads the rendered stack at /repo.
# Every write lands in the disposable e2e clone.
#
# Setup that must happen before the daemon boots (the probe processor, and the
# webhook's rclone_prefix) is done on the host in e2e.sh's stage_checks — both
# are read once at container start, so nothing running inside can change them.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ "${DECREE_PRE_CHECK:-}" = "true" ]; then
    # shellcheck source=../../../../automation/lib/precheck.sh
    source "${SCRIPT_DIR}/../lib/precheck.sh"
    command -v mc >/dev/null 2>&1 || precheck_fail "e2e-minio-file-processing" "mc not found"
    [ -n "${MINIO_ROOT_USER:-}" ] || precheck_fail "e2e-minio-file-processing" "MINIO_ROOT_USER not set"
    command -v rclone >/dev/null 2>&1 || precheck_fail "e2e-minio-file-processing" "rclone not found"
    precheck_pass "e2e-minio-file-processing"
    exit 0
fi

REPO="${E2E_REPO:-/repo}"
INBOX="${E2E_INBOX:-/work/.decree/inbox}"
RUNS="${E2E_RUNS:-/work/.decree/runs}"
MINIO_URL="${MINIO_URL:-http://minio:9000}"
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

# ── 1. MinIO's configured webhook endpoint is actually served ────────────────
#
# The bug this exists for is a wrong PORT in MinIO's notify config, so the
# endpoint has to be read from the rendered compose rather than assumed. The
# original host version probed it from inside the minio container; probing from
# decree tests the same property — both sit on the one exist bridge, so a port
# nothing serves is unreachable from either — and needs no docker socket.
COMPOSE="${REPO}/nas/minio/docker-compose.yml"
[ -f "$COMPOSE" ] || fail "no rendered compose at ${COMPOSE}"
ENDPOINT=$(grep -m1 'MINIO_NOTIFY_WEBHOOK_ENDPOINT_DECREE=' "$COMPOSE" | cut -d= -f2- || true)
[ -n "$ENDPOINT" ] || fail "MINIO_NOTIFY_WEBHOOK_ENDPOINT_DECREE not found in ${COMPOSE}"
say "MinIO is configured to post to ${ENDPOINT}"

HEALTH="${ENDPOINT%/minio}/healthz"
curl -sf --max-time 5 -o /dev/null "$HEALTH" \
    || fail "${HEALTH} is not served — MinIO's notify endpoint points at a dead port"
say "ok    ${HEALTH} reachable"

# ── 2. The rclone remote file-processor downloads through ───────────────────
#
# Written here rather than staged on the host because it is read at routine
# runtime, not at boot — and because the credentials only exist once the
# templates have rendered, which is after staging. /secrets is decree's one
# read-write mount and /secrets/rclone/rclone.conf is the path file-processor
# hardcodes. Named "nextcloud" because that is what the webhook's /minio route
# calls the remote.
mkdir -p /secrets/rclone
cat > /secrets/rclone/rclone.conf << CONF
[nextcloud]
type = s3
provider = Minio
env_auth = false
access_key_id = ${MINIO_ROOT_USER}
secret_access_key = ${MINIO_ROOT_PASSWORD}
endpoint = ${MINIO_URL}
region = us-east-1
CONF
say "wrote rclone remote 'nextcloud' → ${MINIO_URL}"

# ── 3. Bucket, subscribed to the decree webhook target ───────────────────────
mc alias set e2e "$MINIO_URL" "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD" >/dev/null \
    || fail "mc alias set failed against ${MINIO_URL}"
mc mb --ignore-existing "e2e/${BUCKET}" >/dev/null || fail "could not create bucket ${BUCKET}"

# Assert the subscription EXISTS rather than that adding it succeeded: `mc event
# add` errors on an overlapping rule, so a re-run against a stack left standing
# by E2E_KEEP would fail on a bucket that is already correctly wired.
mc event add "e2e/${BUCKET}" arn:minio:sqs::DECREE:webhook --event put >/dev/null 2>&1 || true
mc event ls "e2e/${BUCKET}" 2>/dev/null | grep -q 'arn:minio:sqs::DECREE:webhook' \
    || fail "${BUCKET} is not subscribed to arn:minio:sqs::DECREE:webhook"
say "bucket ${BUCKET} created and subscribed to the decree webhook"

# ── 4. Drop the file in. Everything after this is observation ────────────────
printf '%s' "$TOKEN" > "/tmp/${OBJECT}"
mc cp "/tmp/${OBJECT}" "e2e/${BUCKET}/${OBJECT}" >/dev/null || fail "could not upload ${OBJECT}"
rm -f "/tmp/${OBJECT}"
say "uploaded ${BUCKET}/${OBJECT}"

# ── 5. The event reaches decree ──────────────────────────────────────────────
#
# This is where the assertion stops, and the reason is structural: decree runs
# ONE message at a time, and this check is the message it is running. The
# minio-router message the upload produces is queued BEHIND this routine and
# cannot start until it returns — so no amount of waiting here will ever see the
# processor run.
#
# What is left to prove is therefore graded elsewhere, by properties that cost
# no new mechanism:
#
#   the event arrived            asserted here — a minio-router message is in
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
# The budget is generous because it waits on a QUEUE and on MinIO's own notify
# retry, not on the pipeline; measured, the webhook enqueues in well under a
# second once MinIO has fired.
# Look in the INBOX, not in runs/. A run directory is created when decree starts
# processing a message, and decree runs one message at a time — this check IS the
# message it is running, so the router's run dir cannot exist yet by construction.
# Watching runs/ here waits out the full timeout on a chain that is working.
#
# And match the routine KEY, not a bare "minio-router": that string also appears
# in this check's own message.md, in its needs_routines, so a loose grep reported
# success before MinIO had sent anything at all.
_router_queued() {
    grep -lq '^routine: minio-router' "$INBOX"/*.md 2>/dev/null \
        || grep -rlq '^routine: minio-router' "$RUNS"/*/message.md 2>/dev/null
}
until_ok "MinIO event reached decree as a minio-router message" 180 _router_queued \
    || fail "the webhook never enqueued anything — MinIO posted, but nothing arrived"

say "chain wired; minio-router is queued behind this check"
say "probe object: ${BUCKET}/${OBJECT}"
