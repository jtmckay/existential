#!/usr/bin/env bash
# e2e_file_processing — the Nextcloud → webhook → router → processor chain.
#
# Staged into the clone's scripts/ by e2e.sh, with 10-file-processing.yml as
# its machine, and triggered by the message in 10-file-processing.md. Runs inside
# the `automation` daemon, so it reaches Nextcloud over the exist bridge. Every
# write lands in the disposable e2e clone.
set -euo pipefail

: "${NEXTCLOUD_ADMIN_USER:?NEXTCLOUD_ADMIN_USER not set}"

NEXTCLOUD_URL="${NEXTCLOUD_URL:-http://nextcloud}"
INBOX="${E2E_INBOX:-/work/.decree/inbox}"
RUNS="${E2E_RUNS:-/work/.decree/runs}"
DIR="e2e-flow"
TOKEN="e2eprobe$(date +%s%N)"
OBJECT="probe-${TOKEN}.txt"

say()  { printf '  %s\n' "$*"; }
fail() { printf '  FAIL  %s\n' "$*" >&2; exit 1; }

nc_curl() {
    curl -fsS --max-time 15 -u "${NEXTCLOUD_ADMIN_USER}:${NEXTCLOUD_ADMIN_PASSWORD}" "$@"
}

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

# ── 1. The registered webhook endpoint is actually served ────────────────────
#
# A wrong port here is the bug this exists for, so the endpoint is READ from
# Nextcloud — what it will really post to — not assumed.
ENDPOINT=$(nc_curl -H "OCS-APIRequest: true" -H "Accept: application/json" \
        "${NEXTCLOUD_URL}/ocs/v2.php/apps/webhook_listeners/api/v1/webhooks" \
    | jq -r '.ocs.data[] | select(.event | endswith("NodeWrittenEvent")) | .uri' | head -1) \
    || fail "could not list Nextcloud's webhooks"
[ -n "$ENDPOINT" ] || fail "no NodeWrittenEvent webhook registered — did the nextcloud-file-events migration run?"
say "nextcloud posts file events to ${ENDPOINT}"

HEALTH="${ENDPOINT%/files}/healthz"
curl -sf --max-time 5 -o /dev/null "$HEALTH" \
    || fail "${HEALTH} is not served — the webhook points at a dead port"
say "ok    ${HEALTH} reachable"

# ── 2. Drop the file in. Everything after this is observation ────────────────
_dav="${NEXTCLOUD_URL}/remote.php/dav/files/${NEXTCLOUD_ADMIN_USER}"
nc_curl -o /dev/null -X MKCOL "${_dav}/${DIR}" 2>/dev/null || true
printf '%s' "$TOKEN" | nc_curl -o /dev/null -T - "${_dav}/${DIR}/${OBJECT}" \
    || fail "could not upload ${OBJECT}"
say "uploaded ${DIR}/${OBJECT}"

# ── 3. The event reaches decree ──────────────────────────────────────────────
#
# This is where the assertion stops, and the reason is structural: decree runs
# ONE message at a time, and this check is the message it is running. The
# file_router message the upload produces is queued BEHIND this run and
# cannot start until it returns — so no amount of waiting here will ever see the
# processor run.
#
# What is left to prove is graded elsewhere, by properties that cost no new
# mechanism:
#
#   the event arrived            asserted here — a file_router message is in the
#                                inbox. A wrong port, or no job runner, means
#                                nothing arrives.
#   the router matched it, and
#   the processor read the file  the example processor staged as the probe
#                                asserts its download is non-empty and exits
#                                non-zero otherwise, so a break fails
#                                that run.
#   nothing broke                every run in the clone is graded, so the
#                                router's and the processor's own runs each get
#                                a row of their own.
#
# Look in the INBOX, not in runs/: this check IS the message decree is running,
# so the router's run dir cannot exist yet by construction. And match the
# machine KEY, not a bare "file_router": that string also appears in this
# check's own message.md, in its prose.
_router_queued() {
    grep -lq '^machine: file_router' "$INBOX"/*.md 2>/dev/null \
        || grep -rlq '^machine: file_router' "$RUNS"/*/message.md 2>/dev/null
}
until_ok "nextcloud event reached decree as a file_router message" 180 _router_queued \
    || fail "the webhook never enqueued anything — is nextcloud-cron running its worker?"

say "chain wired; file_router is queued behind this check"
say "probe file: ${DIR}/${OBJECT}"
