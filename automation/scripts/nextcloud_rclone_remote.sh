#!/usr/bin/env bash
# nextcloud-rclone-remote — configure the "nextcloud" rclone remote that
# file-processor (and any file processor with rclone_src=nextcloud) uses to
# download files through Nextcloud's WebDAV — every path file-router emits,
# including the /workspace mount.
#
# Runs as a decree migration (once). An existing [nextcloud]
# stanza in rclone.conf is replaced to allow updates to credentials or URLs.
#
# Env vars (passed through the decree container's compose env):
#   NEXTCLOUD_ADMIN_USER / NEXTCLOUD_ADMIN_PASSWORD
#   NEXTCLOUD_URL         default http://nextcloud
#   NEXTCLOUD_APP_PASSWORD (Optional: use for WebDAV auth)
set -euo pipefail

RCLONE_CONFIG="${SECRETS_DIR:-/secrets}/rclone/rclone.conf"
NEXTCLOUD_URL="${NEXTCLOUD_URL:-http://nextcloud}"

: "${NEXTCLOUD_ADMIN_USER:?NEXTCLOUD_ADMIN_USER not set}"
: "${NEXTCLOUD_ADMIN_PASSWORD:?NEXTCLOUD_ADMIN_PASSWORD not set}"

mkdir -p "$(dirname "${RCLONE_CONFIG}")"
touch "${RCLONE_CONFIG}"

# Drop an existing [nextcloud] section — from its header up to the next
# section header — so a re-run replaces it and keeps every other remote.
_kept=$(awk '/^\[/ { skip = ($0 == "[nextcloud]") } !skip' "${RCLONE_CONFIG}")
printf '%s\n' "$_kept" > "${RCLONE_CONFIG}"

# Determine the best password (App Password > Admin Password)
PASS="${NEXTCLOUD_APP_PASSWORD:-${NEXTCLOUD_ADMIN_PASSWORD}}"
_pass_obs=$(rclone obscure "$PASS")

# Construct the WebDAV URL
# We ensure it points to the root of the user's files via /remote.php/dav/files/USER/
WV_URL="${NEXTCLOUD_URL}/remote.php/dav/files/${NEXTCLOUD_ADMIN_USER}/"

cat <<EOF >> "${RCLONE_CONFIG}"

[nextcloud]
type = webdav
url = ${WV_URL}
vendor = nextcloud
user = ${NEXTCLOUD_ADMIN_USER}
pass = ${_pass_obs}

EOF

echo "Configured rclone remote 'nextcloud' -> ${WV_URL}"
