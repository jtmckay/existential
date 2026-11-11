---
machine: plugin
automation: nextcloud_calendar
chart:
  description: Install and enable Nextcloud's Calendar app.
  initial: wait_for_nextcloud
  states:
    # First boot runs this before nextcloud has finished starting.
    wait_for_nextcloud:
      invoke:
        script: {name: wait_for_nextcloud, timeout: 10m}
      transitions: {done: nextcloud_calendar}
    nextcloud_calendar:
      invoke: nextcloud_calendar
      transitions: {done: done}
    done: {final: true}
    failed: {final: true}
scripts:
  nextcloud_calendar: |
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

    : "${NEXTCLOUD_ADMIN_USER:?NEXTCLOUD_ADMIN_USER not set}"
    : "${NEXTCLOUD_ADMIN_PASSWORD:?NEXTCLOUD_ADMIN_PASSWORD not set}"

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
# nextcloud_calendar

Install and enable Nextcloud's Calendar app.
