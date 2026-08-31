#!/usr/bin/env bash
# minio-bucket — create a MinIO bucket if it does not already exist.
#
# Runs as a decree migration (once) or cron. Idempotent: an existing bucket is
# left untouched, so re-running is a no-op.
#
# Uses rclone rather than mc: rclone ships in the decree image, mc does not, and
# the remote is configured entirely from RCLONE_CONFIG_* env so nothing has to
# be written into automations/secrets/rclone/rclone.conf.
#
# Env vars (set via migration/cron frontmatter):
#   BUCKET       bucket name to create, e.g. "nextcloud"
#
# Env vars (passed through the decree container's compose env):
#   MINIO_ROOT_USER / MINIO_ROOT_PASSWORD   MinIO credentials
#   MINIO_URL                               optional, default http://minio:9000
set -euo pipefail

if [[ "${DECREE_PRE_CHECK:-}" == "true" ]]; then
    command -v rclone >/dev/null 2>&1   || { echo "rclone not found" >&2; exit 1; }
    [[ -n "${BUCKET:-}" ]]              || { echo "BUCKET not set in frontmatter" >&2; exit 1; }
    [[ -n "${MINIO_ROOT_USER:-}" ]]     || { echo "MINIO_ROOT_USER not set" >&2; exit 1; }
    [[ -n "${MINIO_ROOT_PASSWORD:-}" ]] || { echo "MINIO_ROOT_PASSWORD not set" >&2; exit 1; }
    exit 0
fi

export RCLONE_CONFIG_MINIO_TYPE=s3
export RCLONE_CONFIG_MINIO_PROVIDER=Minio
export RCLONE_CONFIG_MINIO_ENV_AUTH=false
export RCLONE_CONFIG_MINIO_ENDPOINT="${MINIO_URL:-http://minio:9000}"
export RCLONE_CONFIG_MINIO_REGION="${MINIO_REGION:-us-east-1}"
export RCLONE_CONFIG_MINIO_ACCESS_KEY_ID="${MINIO_ROOT_USER}"
export RCLONE_CONFIG_MINIO_SECRET_ACCESS_KEY="${MINIO_ROOT_PASSWORD}"

if rclone lsd "minio:${BUCKET}" >/dev/null 2>&1; then
    echo "Bucket '${BUCKET}' already exists — nothing to do."
    exit 0
fi

echo "Creating bucket '${BUCKET}'..."
rclone mkdir "minio:${BUCKET}"
rclone lsd "minio:${BUCKET}" >/dev/null
echo "Bucket '${BUCKET}' created."
