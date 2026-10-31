#!/usr/bin/env bash
# wait_for_immich — the first state of every Immich migration machine. A first
# start runs database migrations before the API answers; /api/server/ping says
# {"res":"pong"} once it does, the same check as the image's own healthcheck.
# The machine's timeout bounds it.
set -uo pipefail

url="${IMMICH_URL:-http://immich-server:2283}/api/server/ping"
until curl -sS --max-time 5 "$url" 2>/dev/null | grep -q '"res":"pong"'; do
    echo "immich not ready (${url}) — retrying in 10s"
    sleep 10
done
echo "immich ready."
