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
