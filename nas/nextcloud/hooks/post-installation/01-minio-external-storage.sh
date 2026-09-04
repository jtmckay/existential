#!/bin/sh
# Mount the MinIO bucket as a Nextcloud external storage folder.
#
# Runs INSIDE the nextcloud container, as root, exactly once — the image's
# entrypoint calls run_path post-installation right after a successful
# `occ maintenance:install` (see /entrypoint.sh). That is the only moment occ
# exists, the DB is populated, and no user has logged in yet. Needs the exec
# bit: run_path skips scripts that lack it.
#
# Object keys under this mount are real file paths, which is what
# automation/shared_routines/minio-router.sh assumes when it turns a MinIO
# webhook event into "${rclone_src}:${prefix}${object_key}". Primary object
# storage (OBJECTSTORE_S3_*) would be less code here but stores opaque
# urn:oid:N keys and would break that pipeline.
#
# Idempotent and non-fatal by design: it exits 0 on every path. A MinIO that is
# disabled, slow or misconfigured must never take the Nextcloud install down
# with it — an install that fails leaves the user staring at the setup wizard.

set -u

# MinIO not enabled (or credentials not rendered) — nothing to mount.
[ -n "${NEXTCLOUD_S3_KEY:-}" ] && [ -n "${NEXTCLOUD_S3_BUCKET:-}" ] || exit 0

occ() { php /var/www/html/occ "$@"; }

if occ files_external:list --output=json 2>/dev/null | grep -q '"mount_point":"/S3"'; then
    echo "==> S3 external storage already configured — nothing to do"
    exit 0
fi

{
    occ app:enable files_external

    # files_external:create prints the new mount id on stdout.
    id=$(occ files_external:create "S3" amazons3 amazons3::accesskey) || exit 1
    id=$(printf '%s' "$id" | tr -dc '0-9')
    [ -n "$id" ] || exit 1

    occ files_external:config "$id" bucket         "$NEXTCLOUD_S3_BUCKET"
    occ files_external:config "$id" hostname       "${NEXTCLOUD_S3_HOST:-minio}"
    occ files_external:config "$id" port           "${NEXTCLOUD_S3_PORT:-9000}"
    occ files_external:config "$id" region         "${NEXTCLOUD_S3_REGION:-us-east-1}"
    occ files_external:config "$id" use_ssl        false
    occ files_external:config "$id" use_path_style true
    occ files_external:config "$id" legacy_auth    false
    occ files_external:config "$id" key            "$NEXTCLOUD_S3_KEY"
    occ files_external:config "$id" secret         "$NEXTCLOUD_S3_SECRET"

    # No files_external:applicable call: a system mount created with neither
    # --user nor --group is already applicable to All users (verify with
    # `occ files_external:list`), and --add-all is not a real option.

    echo "==> Mounted MinIO bucket '$NEXTCLOUD_S3_BUCKET' at /S3 (mount $id)"
} || echo "==> WARNING: could not configure the MinIO external storage; add it by hand in Settings -> External storage"

exit 0
