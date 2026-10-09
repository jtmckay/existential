#!/usr/bin/env bash
# nextcloud-file-events — point Nextcloud's file events at decree's /files webhook.
#
# Runs as a decree migration (once). Uses webhook_listeners' OCS API, which
# ships enabled in nextcloud:34.0.3 (verified) — there is no occ command that
# creates a webhook, and decree has no docker socket anyway.
#
# One webhook per event: Written (new file AND overwrite — Created would double
# every upload), Deleted, Renamed. file-router reads all three.
#
# Nextcloud's side of the wiring (allow_local_remote_servers, the job runner)
# is the nextcloud service's own — nas/nextcloud/hooks/before-starting/
# 02-workspace.sh and the nextcloud-cron container.
#
# Env vars (passed through the decree container's compose env):
#   NEXTCLOUD_URL                              default http://nextcloud
#   NEXTCLOUD_ADMIN_USER / NEXTCLOUD_ADMIN_PASSWORD
#   FILES_WEBHOOK_TOKEN                        EXIST_DECREE_FILES_WEBHOOK_AUTH_TOKEN
#   FILES_WEBHOOK_URI                          default http://automation-webhook:8801/files
set -euo pipefail

NEXTCLOUD_URL="${NEXTCLOUD_URL:-http://nextcloud}"
FILES_WEBHOOK_URI="${FILES_WEBHOOK_URI:-http://automation-webhook:8801/files}"

: "${NEXTCLOUD_ADMIN_USER:?NEXTCLOUD_ADMIN_USER not set}"
: "${NEXTCLOUD_ADMIN_PASSWORD:?NEXTCLOUD_ADMIN_PASSWORD not set}"
: "${FILES_WEBHOOK_TOKEN:?FILES_WEBHOOK_TOKEN not set}"

_api="${NEXTCLOUD_URL}/ocs/v2.php/apps/webhook_listeners/api/v1/webhooks"
_ocs() {
    curl -fsS --max-time 15 -u "${NEXTCLOUD_ADMIN_USER}:${NEXTCLOUD_ADMIN_PASSWORD}" \
        -H "OCS-APIRequest: true" -H "Accept: application/json" "$@"
}

for _event in NodeWrittenEvent NodeDeletedEvent NodeRenamedEvent; do
    jq -n --arg uri "$FILES_WEBHOOK_URI" --arg ev "OCP\\Files\\Events\\Node\\${_event}" \
          --arg auth "Bearer ${FILES_WEBHOOK_TOKEN}" \
          '{httpMethod: "POST", uri: $uri, event: $ev, authMethod: "header", authData: {Authorization: $auth}}' \
        | _ocs -X POST -H "Content-Type: application/json" --data @- "${_api}" >/dev/null
    echo "Registered ${_event} -> ${FILES_WEBHOOK_URI}"
done
