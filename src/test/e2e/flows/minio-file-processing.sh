#!/usr/bin/env bash
# Flow: object written to MinIO → S3 event → decree-webhook → inbox →
#       minio-router → file-processor → the processor actually runs.
#
# This is the chain no per-service exist.test.sh can see. Each service was
# individually healthy the whole time MinIO was posting its events to port
# 48880, which nothing listened on — decree's own test probes 8801 and passed,
# because it was asking the one side that was never wrong. A flow test asks the
# question the user actually cares about: if I drop a file in, does the thing
# happen?
#
# Runs on the host (it needs docker). Every write lands inside the disposable
# e2e clone ($WORK) or inside containers that are torn down with it, so there is
# nothing to clean up and nothing outside the clone is touched.
#
# Contract with e2e.sh: declare FLOW_NAME and FLOW_REQUIRES, exit 0 on pass.
FLOW_NAME="MinIO file-processing pipeline"
FLOW_REQUIRES="EXIST_IS_NAS_MINIO EXIST_IS_SERVICES_DECREE"
set -euo pipefail

# shellcheck disable=SC2034  # read out of this file by e2e.sh, not sourced
: "$FLOW_NAME" "$FLOW_REQUIRES"

WORK="${WORK:?}"
BUCKET="e2e-flow"
TOKEN="e2eprobe$(date +%s%N)"
OBJECT="probe-${TOKEN}.txt"

say()  { printf '[flow]   %s\n' "$*"; }
fail() { printf '[flow]   ✗ %s\n' "$*" >&2; exit 1; }

# Poll until a command succeeds. Cheaper and far less flaky than a fixed sleep:
# the decree daemon's inbox scan and the model-free processor are both fast, but
# a loaded CI box is not.
until_ok() {
    local what="$1" timeout="$2"; shift 2
    local deadline=$(( SECONDS + timeout ))
    while [ "$SECONDS" -lt "$deadline" ]; do
        if "$@" >/dev/null 2>&1; then
            say "✓ ${what}"
            return 0
        fi
        sleep 2
    done
    fail "${what} — not observed within ${timeout}s"
}

# ── 0. The webhook is reachable from MinIO, at the port MinIO is configured to
#       use. Asserted from inside the minio container on purpose: reachability
#       from anywhere else is not the property that broke.
# `|| true` on every extraction below: under `set -e` a failing command
# substitution aborts the script before the next line runs, which would
# replace these named failures with a bare grep error and no context.
ENDPOINT=$(grep -m1 'MINIO_NOTIFY_WEBHOOK_ENDPOINT_DECREE=' "$WORK/nas/minio/docker-compose.yml" 2>/dev/null | cut -d= -f2- || true)
[ -n "$ENDPOINT" ] || fail "MINIO_NOTIFY_WEBHOOK_ENDPOINT_DECREE not found in the generated compose"
say "MinIO is configured to post to ${ENDPOINT}"
HEALTH="${ENDPOINT%/minio}/healthz"
docker exec minio curl -sf --max-time 5 -o /dev/null "$HEALTH" \
    || fail "minio cannot reach ${HEALTH} — the notify endpoint points at a port nothing serves"
say "✓ minio → ${HEALTH} reachable"

# ── 1. rclone remote. file-processor downloads through it, and the webhook's
#       /minio route names the remote "nextcloud", so that is the remote's name.
MINIO_USER=$(grep -m1 '^MINIO_ROOT_USER=' "$WORK/nas/minio/.env" 2>/dev/null | cut -d= -f2- || true)
MINIO_PASS=$(grep -m1 '^MINIO_ROOT_PASSWORD=' "$WORK/nas/minio/.env" 2>/dev/null | cut -d= -f2- || true)
[ -n "$MINIO_USER" ] && [ -n "$MINIO_PASS" ] || fail "could not read MinIO root credentials from the clone"

mkdir -p "$WORK/automations/secrets/rclone"
cat > "$WORK/automations/secrets/rclone/rclone.conf" << CONF
[nextcloud]
type = s3
provider = Minio
env_auth = false
access_key_id = ${MINIO_USER}
secret_access_key = ${MINIO_PASS}
endpoint = http://minio:9000
region = us-east-1
CONF
say "wrote rclone remote 'nextcloud' → http://minio:9000"

# ── 2. A processor that matches only this run's bucket and needs no model.
#       CRITERIA is deliberately empty: the natural-language gate costs a model
#       call, and this test is about wiring, not judgment.
mkdir -p "$WORK/automations/lib/file-processors"
cat > "$WORK/automations/lib/file-processors/e2e-probe.sh" << PROC
#!/usr/bin/env bash
# shellcheck disable=SC2034
PATTERN="nextcloud:${BUCKET}/.*\.txt"
CRITERIA=""
IS_PRE_SIGNED=false
set -euo pipefail
if [ "\$FILE_ACTION" = "removed" ]; then
    echo "E2E-PROBE removed \$FILE_KEY"
    exit 0
fi
echo "E2E-PROBE-SOURCE \$FILE_SOURCE"
echo "E2E-PROBE-OK \$(cat "\$FILE_PATH")"
PROC
say "installed processor e2e-probe.sh (PATTERN=nextcloud:${BUCKET}/.*\\.txt)"

# ── 2b. Enable the two routines the pipeline needs. They ship `enabled: false`
#       on purpose -- the pipeline is opt-in, and the auto-file-processing quest
#       tells you to turn them on by hand (its step 1). The flow does exactly
#       what that step does, so what runs here is the documented setup and not a
#       private arrangement the quest never mentions.
CONFIG="$WORK/services/decree/decree/config.yml"
[ -f "$CONFIG" ] || fail "decree config.yml not rendered in the clone"
for _routine in minio-router file-processor; do
    awk -v r="$_routine" '
        $0 ~ "^  " r ":$" { print; inblock = 1; next }
        inblock && /^ *enabled:/ { sub(/false/, "true"); inblock = 0 }
        { print }
    ' "$CONFIG" > "${CONFIG}.tmp" && mv "${CONFIG}.tmp" "$CONFIG"
    grep -A1 "^  ${_routine}:$" "$CONFIG" | grep -q "enabled: true" \
        || fail "could not enable ${_routine} in config.yml"
done
say "enabled minio-router and file-processor"

# config.yml is read at boot, so the daemon has to be restarted to see it --
# again exactly what the quest says (its step 3).
docker restart decree >/dev/null || fail "could not restart decree"
until_ok "decree back up after restart" 60 docker exec decree true
say "restarted decree to pick up the routine config"

# ── 2c. Point the webhook's rclone_prefix at this run's bucket.
#
#       minio-router DROPS the S3 bucket when it builds FILE_SOURCE -- it emits
#       "<rclone_src>:<rclone_prefix>/<object-key>". That is right for the
#       topology it was written for, where the bucket IS a nextcloud external
#       mount and the nextcloud-side path is the prefix. But this flow talks to
#       MinIO directly through an s3 remote, where the first path segment must
#       be the bucket -- so the prefix is where the bucket has to go.
PREFIX_CONFIG="$WORK/services/decree/webhook/config.yml"
[ -f "$PREFIX_CONFIG" ] || fail "webhook config.yml not rendered in the clone"
awk -v b="$BUCKET" '
    /^  - path: \/minio$/ { inblock = 1 }
    inblock && /^      rclone_prefix:/ { print "      rclone_prefix: " b; inblock = 0; next }
    { print }
' "$PREFIX_CONFIG" > "${PREFIX_CONFIG}.tmp" && mv "${PREFIX_CONFIG}.tmp" "$PREFIX_CONFIG"
grep -q "rclone_prefix: ${BUCKET}" "$PREFIX_CONFIG" \
    || fail "could not set rclone_prefix to ${BUCKET}"
docker restart decree-webhook >/dev/null || fail "could not restart decree-webhook"
until_ok "decree-webhook back up after restart" 60 \
    docker exec minio curl -sf --max-time 3 -o /dev/null "$HEALTH"
say "set rclone_prefix=${BUCKET} and restarted decree-webhook"

# ── 3. Bucket, subscribed to the decree webhook target.
# Credentials come from the container's own environment rather than this
# script's argv, so they never appear in a host process list or an e2e log.
docker exec minio sh -c \
    'mc alias set e2e http://127.0.0.1:9000 "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD"' >/dev/null \
    || fail "mc alias set failed"
docker exec minio mc mb --ignore-existing "e2e/${BUCKET}" >/dev/null \
    || fail "could not create bucket ${BUCKET}"
# Assert the subscription EXISTS rather than that adding it succeeded: `mc event
# add` errors on an overlapping rule, so a re-run against a stack left standing
# by E2E_KEEP would fail on a bucket that is already correctly wired.
docker exec minio mc event add "e2e/${BUCKET}" arn:minio:sqs::DECREE:webhook --event put >/dev/null 2>&1 || true
docker exec minio mc event ls "e2e/${BUCKET}" 2>/dev/null | grep -q 'arn:minio:sqs::DECREE:webhook' \
    || fail "${BUCKET} is not subscribed to arn:minio:sqs::DECREE:webhook"
say "bucket ${BUCKET} created and subscribed to the decree webhook"

# ── 4. Drop the file in. Everything after this is observation.
printf '%s' "$TOKEN" | docker exec -i minio sh -c "cat > /tmp/${OBJECT}"
docker exec minio mc cp "/tmp/${OBJECT}" "e2e/${BUCKET}/${OBJECT}" >/dev/null \
    || fail "could not upload ${OBJECT}"
say "uploaded ${BUCKET}/${OBJECT}"

# ── 5. The chain, asserted one link at a time so a break names itself.
_router_queued() { grep -rlq "minio-router" "$WORK/automations/runs"/*/message.md; }
until_ok "MinIO event reached decree as a minio-router message" 60 _router_queued

_processor_ran() { grep -rq "E2E-PROBE-OK ${TOKEN}" "$WORK/automations/runs"/*/routine.log; }
until_ok "file-processor ran e2e-probe on the uploaded object" 120 _processor_ran

# ── 6. And it succeeded. A routine that runs and fails is not a passing flow.
RUN_DIR=$(grep -rl "E2E-PROBE-OK ${TOKEN}" "$WORK/automations/runs"/*/routine.log 2>/dev/null | head -1 || true)
RUN_DIR=$(dirname "$RUN_DIR")
[ -f "$RUN_DIR/run.json" ] \
    || fail "$(basename "$RUN_DIR") produced no run.json — decree could not finalize the message"
EXIT_CODE=$(grep -o '"exit_code"[[:space:]]*:[[:space:]]*[0-9-]*' "$RUN_DIR/run.json" | grep -o '[0-9-]*$' || true)
[ "$EXIT_CODE" = "0" ] \
    || fail "$(basename "$RUN_DIR") exited ${EXIT_CODE}: $(tail -5 "$RUN_DIR/routine.log")"
say "✓ run $(basename "$RUN_DIR") exit_code=0"

# ── 7. No message may be left stuck. A routine that runs but never gets its
#       run.json written comes back on every tick forever — that is exactly how
#       the triage YAML bug hid, so the flow refuses to pass with a live inbox.
# `|| true` for the same reason as the extractions above, and it bites harder
# here: a missing dead/ dir makes find exit 1, pipefail propagates it to the
# assignment, and set -e kills the script with NO message -- a test that fails
# silently is worse than no test.
STUCK=$(find "$WORK/services/decree/decree/inbox" -maxdepth 1 -name '*.md' 2>/dev/null | wc -l || true)
[ "$STUCK" -eq 0 ] \
    || fail "${STUCK} message(s) still stuck in the inbox: $(find "$WORK/services/decree/decree/inbox" -maxdepth 1 -name '*.md' -printf '%f ')"
say "✓ inbox drained, nothing stuck"

DEAD=$(find "$WORK/services/decree/decree/inbox/dead" -maxdepth 1 -name '*.md' 2>/dev/null | wc -l || true)
[ "$DEAD" -eq 0 ] \
    || fail "${DEAD} message(s) dead-lettered: $(find "$WORK/services/decree/decree/inbox/dead" -maxdepth 1 -name '*.md' -printf '%f ')"
say "✓ no dead letters"
