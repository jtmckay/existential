#!/usr/bin/env bash
# minio-bucket-webhook — subscribe a MinIO bucket to the DECREE webhook target.
#
# Runs as a decree migration (once) or cron. Idempotent: `mc event add` errors
# on an already-subscribed overlapping rule, so this checks `mc event ls`
# first and leaves an existing subscription alone.
#
# Subscribing a bucket applies to EVERYTHING written to it, not just whatever
# one thing prompted you to subscribe it — every future PUT/DELETE in that
# bucket fires the webhook from then on. Fine for a bucket the automation
# pipeline should watch in general; think twice before pointing this at a
# bucket other things write to for unrelated reasons.
#
# Uses mc rather than rclone: bucket event notifications are MinIO's admin
# API, which is not S3. The alias is configured entirely from MC_HOST_* env,
# the same trick minio-service-account.sh uses, so nothing has to be written
# into automation/secrets.
#
# Env vars (set via migration/cron frontmatter):
#   BUCKET   bucket to subscribe, e.g. "nextcloud"
#   EVENTS   comma-separated MinIO event types, default "put,delete"
#   ARN      webhook target ARN, default arn:minio:sqs::DECREE:webhook
#            (see services/automation/webhook/config.yml's /minio endpoint,
#            and nas/minio/docker-compose.yml's MINIO_NOTIFY_WEBHOOK_* env —
#            that DECREE identifier is what MinIO derives this ARN from)
#
# Env vars (passed through the decree container's compose env):
#   MINIO_ROOT_USER / MINIO_ROOT_PASSWORD   MinIO admin credentials
#   MINIO_URL                               optional, default http://minio:9000
set -euo pipefail

BUCKET="${BUCKET:-}"
EVENTS="${EVENTS:-put,delete}"
ARN="${ARN:-arn:minio:sqs::DECREE:webhook}"

if [[ "${DECREE_PRE_CHECK:-}" == "true" ]]; then
    command -v mc >/dev/null 2>&1       || { echo "mc not found" >&2; exit 1; }
    [[ -n "${BUCKET:-}" ]]              || { echo "BUCKET not set in frontmatter" >&2; exit 1; }
    [[ -n "${MINIO_ROOT_USER:-}" ]]     || { echo "MINIO_ROOT_USER not set" >&2; exit 1; }
    [[ -n "${MINIO_ROOT_PASSWORD:-}" ]] || { echo "MINIO_ROOT_PASSWORD not set" >&2; exit 1; }
    exit 0
fi

export MC_HOST_minio="${MINIO_URL:-http://minio:9000}"
MC_HOST_minio="${MC_HOST_minio/:\/\//://${MINIO_ROOT_USER}:${MINIO_ROOT_PASSWORD}@}"

if mc event ls "minio/${BUCKET}" 2>/dev/null | grep -q "${ARN}"; then
    echo "Bucket '${BUCKET}' is already subscribed to ${ARN} — leaving it alone."
    exit 0
fi

mc event add "minio/${BUCKET}" "${ARN}" --event "${EVENTS}"
echo "Subscribed bucket '${BUCKET}' to ${ARN} (events: ${EVENTS})."
