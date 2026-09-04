#!/usr/bin/env bash
# minio-service-account — create a bucket-scoped MinIO identity for a service.
#
# Runs as a decree migration (once) or cron. Idempotent: an existing user/policy
# is updated in place to match the rendered credentials, so re-running is safe.
#
# Uses mc rather than rclone: creating users and policies is MinIO's admin API,
# which is not S3, so rclone cannot reach it. The alias is configured entirely
# from MC_HOST_* env so nothing has to be written into automation/secrets.
# That env form URL-embeds the root credentials — a root password containing
# '/', '@' or ':' would break it. EXIST_24_CHAR_PASSWORD's charset cannot
# produce those, but a hand-edited password could.
#
# Env vars (set via migration/cron frontmatter):
#   BUCKET       bucket the identity is scoped to, e.g. "nextcloud"
#   SVC_USER     access key to create; defaults to MINIO_<BUCKET>_ACCESS_KEY
#   SVC_SECRET   secret key to set;    defaults to MINIO_<BUCKET>_SECRET_KEY
#
# Env vars (passed through the decree container's compose env):
#   MINIO_ROOT_USER / MINIO_ROOT_PASSWORD   MinIO admin credentials
#   MINIO_<BUCKET>_ACCESS_KEY / _SECRET_KEY the identity, rendered from .env
#   MINIO_URL                               optional, default http://minio:9000
set -euo pipefail

# The per-service credential env vars are named after the bucket, so one routine
# serves every consumer: BUCKET=nextcloud reads MINIO_NEXTCLOUD_ACCESS_KEY.
_bucket_env_prefix() {
    printf 'MINIO_%s' "$(printf '%s' "${BUCKET:-}" | tr '[:lower:]-' '[:upper:]_')"
}

if [[ -n "${BUCKET:-}" ]]; then
    _prefix="$(_bucket_env_prefix)"
    _user_var="${_prefix}_ACCESS_KEY"
    _secret_var="${_prefix}_SECRET_KEY"
    SVC_USER="${SVC_USER:-${!_user_var:-}}"
    SVC_SECRET="${SVC_SECRET:-${!_secret_var:-}}"
fi

if [[ "${DECREE_PRE_CHECK:-}" == "true" ]]; then
    command -v mc >/dev/null 2>&1      || { echo "mc not found" >&2; exit 1; }
    [[ -n "${BUCKET:-}" ]]             || { echo "BUCKET not set in frontmatter" >&2; exit 1; }
    [[ -n "${SVC_USER:-}" ]]           || { echo "SVC_USER not set" >&2; exit 1; }
    [[ -n "${SVC_SECRET:-}" ]]         || { echo "SVC_SECRET not set" >&2; exit 1; }
    [[ -n "${MINIO_ROOT_USER:-}" ]]    || { echo "MINIO_ROOT_USER not set" >&2; exit 1; }
    [[ -n "${MINIO_ROOT_PASSWORD:-}" ]]|| { echo "MINIO_ROOT_PASSWORD not set" >&2; exit 1; }
    exit 0
fi

POLICY="${BUCKET}-rw"
export MC_HOST_minio="${MINIO_URL:-http://minio:9000}"
MC_HOST_minio="${MC_HOST_minio/:\/\//://${MINIO_ROOT_USER}:${MINIO_ROOT_PASSWORD}@}"

policy_file="$(mktemp)"
trap 'rm -f "$policy_file"' EXIT
cat > "$policy_file" <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["s3:GetBucketLocation", "s3:ListBucket", "s3:ListBucketMultipartUploads"],
      "Resource": ["arn:aws:s3:::${BUCKET}"]
    },
    {
      "Effect": "Allow",
      "Action": ["s3:*"],
      "Resource": ["arn:aws:s3:::${BUCKET}/*"]
    }
  ]
}
EOF

if mc admin policy info minio "$POLICY" >/dev/null 2>&1; then
    echo "Policy '${POLICY}' already exists — leaving it alone."
else
    echo "Creating policy '${POLICY}' (read/write on bucket '${BUCKET}' only)..."
    mc admin policy create minio "$POLICY" "$policy_file"
fi

# `user add` is an upsert: it resets the secret to the rendered value, which
# keeps .env the source of truth if the two ever drift.
echo "Creating/updating user '${SVC_USER}'..."
mc admin user add minio "$SVC_USER" "$SVC_SECRET"

# A second attach exits non-zero with "policy change is already in effect",
# so only attach when the user does not already carry the policy.
if mc admin user info minio "$SVC_USER" 2>/dev/null | grep -q "$POLICY"; then
    echo "Policy '${POLICY}' already attached to '${SVC_USER}'."
else
    echo "Attaching policy '${POLICY}' to '${SVC_USER}'..."
    mc admin policy attach minio "$POLICY" --user "$SVC_USER"
fi

mc admin user info minio "$SVC_USER" >/dev/null
echo "Service account '${SVC_USER}' ready with '${POLICY}' on bucket '${BUCKET}'."
