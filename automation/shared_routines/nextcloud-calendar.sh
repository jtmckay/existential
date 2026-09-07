#!/usr/bin/env bash
# nextcloud-calendar — install/enable Nextcloud's Calendar app.
#
# Runs as a decree migration (once). Idempotent: install/enable is a no-op on
# an instance that already has it.
#
# Same OCS provisioning-API call nextcloud-richdocuments.sh uses (decree has
# no docker socket, so `occ` is not reachable from here) — verified live
# against nextcloud:34.0.3:
#   POST /ocs/v2.php/cloud/apps/{app}   install+enable an app
#
# The `dav` app (CalDAV/CardDAV) ships enabled in the base image regardless —
# this just turns on the web UI and calendar-specific endpoints on top of it.
# Nextcloud auto-creates a "Personal" calendar and a "Contact birthdays"
# calendar for each user the first time they load Calendar or this app is
# enabled — nothing else to provision.
#
# Env vars (passed through the decree container's compose env):
#   NEXTCLOUD_URL                              default http://nextcloud
#   NEXTCLOUD_ADMIN_USER / NEXTCLOUD_ADMIN_PASSWORD
set -euo pipefail

NEXTCLOUD_URL="${NEXTCLOUD_URL:-http://nextcloud}"

if [[ "${DECREE_PRE_CHECK:-}" == "true" ]]; then
    command -v curl >/dev/null 2>&1         || { echo "curl not found" >&2; exit 1; }
    [[ -n "${NEXTCLOUD_ADMIN_USER:-}" ]]     || { echo "NEXTCLOUD_ADMIN_USER not set" >&2; exit 1; }
    [[ -n "${NEXTCLOUD_ADMIN_PASSWORD:-}" ]] || { echo "NEXTCLOUD_ADMIN_PASSWORD not set" >&2; exit 1; }
    exit 0
fi

echo "Installing/enabling calendar..."
_body=$(mktemp)
_code=$(curl -sS --max-time 15 -o "${_body}" -w '%{http_code}' \
    -u "${NEXTCLOUD_ADMIN_USER}:${NEXTCLOUD_ADMIN_PASSWORD}" \
    -H "OCS-APIRequest: true" -X POST "${NEXTCLOUD_URL}/ocs/v2.php/cloud/apps/calendar" \
    -d "format=json")
if [[ "${_code}" != "200" ]]; then
    echo "  POST /ocs/v2.php/cloud/apps/calendar -> HTTP ${_code}: $(cat "${_body}")" >&2
    rm -f "${_body}"
    exit 1
fi
rm -f "${_body}"

echo "calendar app installed and enabled — see https://<nextcloud domain>/apps/calendar"
