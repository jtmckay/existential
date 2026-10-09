#!/usr/bin/env bash
# wait_for_homeassistant — the first state of every Home Assistant migration
# machine.
#
# On a truly fresh volume, services/homeassistant/entrypoint.sh guarantees HA
# restarts itself exactly once, ~9-10s after first boot, to promote its
# "pending" proxy settings to "stable". /manifest.json answers before that
# restart (it is a static asset, served while HA is still starting up), so
# probing it once would let the migration start right before HA cuts its own
# connections out from under it — the empty-reply / connection-refused failures
# a fresh reset produces.
#
# So: wait until HA has answered CONTINUOUSLY for 30s. The restart lands inside
# that window, and any failed probe starts the count again. The machine's
# timeout bounds the whole wait.
set -uo pipefail

url="${HOMEASSISTANT_URL:-http://homeassistant:8123}/manifest.json"
up_since=""
while :; do
    if curl -fsS --max-time 5 -o /dev/null "$url" 2>/dev/null; then
        up_since="${up_since:-$SECONDS}"
        if (( SECONDS - up_since >= 30 )); then
            echo "homeassistant ready (answering for 30s)."
            exit 0
        fi
    else
        [[ -n "$up_since" ]] && echo "homeassistant stopped answering — starting the count again"
        up_since=""
    fi
    sleep 5
done
