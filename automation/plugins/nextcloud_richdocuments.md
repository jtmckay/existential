---
machine: plugin
automation: nextcloud_richdocuments
chart:
  description: Install richdocuments and point it at Collabora, with the WOPI allowlist set to the exist bridge.
  data:
    WOPI_ALLOWLIST: {type: string, default: 172.16.0.0/12}
  initial: wait_for_nextcloud
  states:
    # First boot runs this before nextcloud has finished starting.
    wait_for_nextcloud:
      invoke:
        script: {name: wait_for_nextcloud, timeout: 10m}
      transitions: {done: nextcloud_richdocuments}
    nextcloud_richdocuments:
      invoke: nextcloud_richdocuments
      transitions: {done: done}
    done: {final: true}
    failed: {final: true}
scripts:
  nextcloud_richdocuments: |
    #!/usr/bin/env bash
    # nextcloud-richdocuments — install richdocuments and point it at Collabora,
    # and Collabora back at Nextcloud over the exist network.
    #
    # Runs as a decree migration (once). Idempotent: re-running just re-applies the
    # same values, which is a no-op once they already match.
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
    # Params:
    #   WOPI_ALLOWLIST   CIDR(s) allowed to make WOPI requests, default the exist
    #                    bridge range
    #
    # Env vars (passed through the decree container's compose env):
    #   NEXTCLOUD_URL                              default http://nextcloud
    #   NEXTCLOUD_ADMIN_USER / NEXTCLOUD_ADMIN_PASSWORD
    #   COLLABORA_URL                               e.g. https://collabora.example.com
    #
    # wopi_callback_url is the address Collabora fetches files from. Left blank,
    # richdocuments hands out Nextcloud's public URL, so Collabora goes out through
    # Caddy (and Cloudflare, if fronted) and arrives from a LAN IP that
    # wopi_allowlist denies. http://nextcloud keeps it on the exist network;
    # collabora's aliasgroup1 lists that host.
    set -euo pipefail

    WOPI_ALLOWLIST="$DECREE_DATA_WOPI_ALLOWLIST"
    NEXTCLOUD_URL="${NEXTCLOUD_URL:-http://nextcloud}"

    : "${NEXTCLOUD_ADMIN_USER:?NEXTCLOUD_ADMIN_USER not set}"
    : "${NEXTCLOUD_ADMIN_PASSWORD:?NEXTCLOUD_ADMIN_PASSWORD not set}"
    : "${COLLABORA_URL:?COLLABORA_URL not set}"

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

    echo "Setting wopi_callback_url -> http://nextcloud..."
    _ocs POST "/ocs/v2.php/apps/provisioning_api/api/v1/config/apps/richdocuments/wopi_callback_url" \
        "value=http://nextcloud&format=json" \
        || { echo "Could not set wopi_callback_url." >&2; exit 1; }

    echo "Setting wopi_allowlist -> ${WOPI_ALLOWLIST}..."
    _ocs POST "/ocs/v2.php/apps/provisioning_api/api/v1/config/apps/richdocuments/wopi_allowlist" \
        "value=${WOPI_ALLOWLIST}&format=json" \
        || { echo "Could not set wopi_allowlist." >&2; exit 1; }

    echo "richdocuments configured: wopi_url=${COLLABORA_URL} wopi_callback_url=http://nextcloud wopi_allowlist=${WOPI_ALLOWLIST}"
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
# nextcloud_richdocuments

Install richdocuments and point it at Collabora, with the WOPI allowlist set to the exist bridge.
