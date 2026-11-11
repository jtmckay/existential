---
machine: plugin
automation: nextcloud_file_events
chart:
  description: Register Nextcloud's file-event webhooks (written, deleted, renamed) against automation-webhook's /files.
  initial: wait_for_nextcloud
  states:
    # First boot runs this before nextcloud has finished starting.
    wait_for_nextcloud:
      invoke:
        script: {name: wait_for_nextcloud, timeout: 10m}
      transitions: {done: nextcloud_file_events}
    nextcloud_file_events:
      invoke: nextcloud_file_events
      transitions: {done: done}
    done: {final: true}
    failed: {final: true}
scripts:
  nextcloud_file_events: |
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
  wait_for_nextcloud: |
    #!/usr/bin/env bash
    # wait_for_nextcloud — the first state of every Nextcloud migration machine.
    #
    # None of those migrations retries, and a first-run Nextcloud install takes
    # minutes, so without this they fire at an instance that is still installing,
    # fail, and block every migration behind them. The machine's timeout bounds it.
    #
    # A 200 on /status.php is NOT readiness: an *uninstalled* Nextcloud answers 200
    # with "installed":false, which is exactly what a still-installing (or failed)
    # instance looks like. Match the body, the same way nas/nextcloud/exist.test.sh
    # does — that file is the reference for what "ready" means here.
    set -uo pipefail

    url="${NEXTCLOUD_URL:-http://nextcloud}/status.php"
    until curl -sS --max-time 5 "$url" 2>/dev/null | grep -q '"installed":true'; do
        echo "nextcloud not ready (${url}) — retrying in 10s"
        sleep 10
    done
    echo "nextcloud ready."
---
# nextcloud_file_events

Register Nextcloud's file-event webhooks (written, deleted, renamed) against automation-webhook's /files.
