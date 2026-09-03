#!/usr/bin/env bash
# nextcloud-richdocuments — install richdocuments and point it at Collabora.
#
# Runs as a decree migration (once). Idempotent: re-running just re-applies the
# same three values, which is a no-op once they already match.
#
# Everything here goes over Nextcloud's own HTTP API with admin Basic Auth —
# decree has no docker socket, so `occ` is not reachable from here the way
# nas/nextcloud's own hooks reach it. Verified live against nextcloud:34.0.3
# (installed richdocuments 11.1.0 from a clean instance, both calls below):
#   POST /ocs/v2.php/cloud/apps/{app}                                  install+enable an app
#                                                                       (provisioning_api's
#                                                                       Apps#enable route,
#                                                                       root '/cloud')
#   POST /ocs/v2.php/apps/provisioning_api/api/v1/config/apps/{a}/{k}  set one app config value
#                                                                       (same effect as
#                                                                       `occ config:app:set`)
#
# wopi_allowlist restricts which IPs may act as the WOPI client (i.e. answer
# "give me this file's bytes" on Nextcloud's behalf). richdocuments ships it
# BLANK — WOPIMiddleware::isWOPIAllowed() (lib/Middleware/WOPIMiddleware.php)
# returns true unconditionally when the setting is empty — and its own admin
# UI flags that with a warning (AdminSettings.vue: "users may download
# restricted files via WOPI requests to the Nextcloud server"). The `exist`
# bridge subnet is the right value: same reasoning nextcloud's own
# TRUSTED_PROXIES uses (nas/nextcloud/docker-compose.exist.yml) — trust the
# network the containers actually sit on, not a container IP that moves on
# recreate.
#
# Env vars (set via migration frontmatter):
#   WOPI_ALLOWLIST   CIDR(s) allowed to make WOPI requests, default the exist
#                    bridge range
#
# Env vars (passed through the decree container's compose env):
#   NEXTCLOUD_URL                              default http://nextcloud
#   NEXTCLOUD_ADMIN_USER / NEXTCLOUD_ADMIN_PASSWORD
#   COLLABORA_URL                               e.g. https://collabora.example.com
set -euo pipefail

WOPI_ALLOWLIST="${WOPI_ALLOWLIST:-172.16.0.0/12}"
NEXTCLOUD_URL="${NEXTCLOUD_URL:-http://nextcloud}"

if [[ "${DECREE_PRE_CHECK:-}" == "true" ]]; then
    command -v curl >/dev/null 2>&1         || { echo "curl not found" >&2; exit 1; }
    [[ -n "${NEXTCLOUD_ADMIN_USER:-}" ]]     || { echo "NEXTCLOUD_ADMIN_USER not set" >&2; exit 1; }
    [[ -n "${NEXTCLOUD_ADMIN_PASSWORD:-}" ]] || { echo "NEXTCLOUD_ADMIN_PASSWORD not set" >&2; exit 1; }
    [[ -n "${COLLABORA_URL:-}" ]]            || { echo "COLLABORA_URL not set" >&2; exit 1; }
    exit 0
fi

# _ocs METHOD PATH [FORM_DATA] — Nextcloud's OCS API requires the
# OCS-APIRequest header (its CSRF guard otherwise rejects a request with no
# browser session) and returns 200 with a JSON status field even on a logical
# failure, so check the HTTP code, not just curl's own exit status.
_ocs() {
    local method="$1" path="$2" data="${3:-}" code body
    body=$(mktemp)
    code=$(curl -sS --max-time 10 -o "$body" -w '%{http_code}' \
        -u "${NEXTCLOUD_ADMIN_USER}:${NEXTCLOUD_ADMIN_PASSWORD}" \
        -H "OCS-APIRequest: true" -X "$method" "${NEXTCLOUD_URL}${path}" \
        ${data:+-d "$data"})
    if [[ "$code" != "200" ]]; then
        echo "  ${method} ${path} -> HTTP ${code}: $(cat "$body")" >&2
        rm -f "$body"
        return 1
    fi
    rm -f "$body"
}

echo "Installing/enabling richdocuments..."
_ocs POST "/ocs/v2.php/cloud/apps/richdocuments" "format=json" \
    || { echo "Could not install/enable richdocuments." >&2; exit 1; }

echo "Setting wopi_url -> ${COLLABORA_URL}..."
_ocs POST "/ocs/v2.php/apps/provisioning_api/api/v1/config/apps/richdocuments/wopi_url" \
    "value=${COLLABORA_URL}&format=json" \
    || { echo "Could not set wopi_url." >&2; exit 1; }

echo "Setting wopi_allowlist -> ${WOPI_ALLOWLIST}..."
_ocs POST "/ocs/v2.php/apps/provisioning_api/api/v1/config/apps/richdocuments/wopi_allowlist" \
    "value=${WOPI_ALLOWLIST}&format=json" \
    || { echo "Could not set wopi_allowlist." >&2; exit 1; }

echo "richdocuments configured: wopi_url=${COLLABORA_URL} wopi_allowlist=${WOPI_ALLOWLIST}"
