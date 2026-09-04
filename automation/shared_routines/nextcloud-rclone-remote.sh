#!/usr/bin/env bash
# nextcloud-rclone-remote — configure the "nextcloud" rclone remote that
# file-processor (and any file processor with rclone_src=nextcloud) uses to
# download files reached through Nextcloud's WebDAV — including anything
# under the /S3 external-storage mount, e.g. workspace-pull.sh's live
# MinIO -> local pull for workspace/.
#
# Runs as a decree migration (once). Idempotent: an existing [nextcloud]
# stanza in rclone.conf is left alone — to rotate the password, delete that
# stanza first (or edit it with `rclone config password`) and re-run.
#
# Writes to rclone.conf directly (obscure + append) rather than going through
# ./existential.sh run rclone's interactive wizard: that wizard exists for
# accounts this stack has no other way to learn the credentials for (Dropbox,
# a personal S3 bucket). This Nextcloud instance's admin credentials are
# already fully rendered — there is nothing to ask the user.
#
# Env vars (passed through the decree container's compose env):
#   NEXTCLOUD_ADMIN_USER / NEXTCLOUD_ADMIN_PASSWORD
#   NEXTCLOUD_URL   default http://nextcloud
set -euo pipefail

RCLONE_CONFIG="${SECRETS_DIR:-/secrets}/rclone/rclone.conf"
NEXTCLOUD_URL="${NEXTCLOUD_URL:-http://nextcloud}"

if [[ "${DECREE_PRE_CHECK:-}" == "true" ]]; then
    command -v rclone >/dev/null 2>&1        || { echo "rclone not found" >&2; exit 1; }
    [[ -n "${NEXTCLOUD_ADMIN_USER:-}" ]]     || { echo "NEXTCLOUD_ADMIN_USER not set" >&2; exit 1; }
    [[ -n "${NEXTCLOUD_ADMIN_PASSWORD:-}" ]] || { echo "NEXTCLOUD_ADMIN_PASSWORD not set" >&2; exit 1; }
    exit 0
fi

mkdir -p "$(dirname "${RCLONE_CONFIG}")"
touch "${RCLONE_CONFIG}"

if grep -q '^\[nextcloud\]' "${RCLONE_CONFIG}" 2>/dev/null; then
    echo "rclone remote 'nextcloud' already configured — leaving it alone."
    exit 0
fi

_pass_obs="$(rclone obscure "${NEXTCLOUD_ADMIN_PASSWORD}")"

{
    echo ""
    echo "[nextcloud]"
    echo "type = webdav"
    echo "url = ${NEXTCLOUD_URL}/remote.php/dav/files/${NEXTCLOUD_ADMIN_USER}/"
    echo "vendor = nextcloud"
    echo "user = ${NEXTCLOUD_ADMIN_USER}"
    echo "pass = ${_pass_obs}"
} >> "${RCLONE_CONFIG}"

echo "Configured rclone remote 'nextcloud' -> ${NEXTCLOUD_URL}"
