#!/usr/bin/env bash
# container-health.sh — host-side container-state gate.
#
# Runs where docker is visible (the HOST), NOT inside existential-adhoc.
# Per-service exist.test.sh scripts self-elevate into adhoc, which has no
# docker socket and can only reach services over the network — so they
# structurally cannot detect a daemon that is crash-looping or has no HTTP
# surface (decree main + every *-decree sidecar). This gate fills that gap.
#
# Read-only. Pure observation (docker inspect / docker logs). For every
# container in the given compose project it asserts a healthy steady state:
#   - status == running           (not restarting / exited / dead / created / paused)
#   - not actively restart-looping (RestartCount stable across a short resample)
#   - not flapping                 (RestartCount below FLAP_THRESHOLD)
#   - Health.Status != unhealthy   (starting / healthy / none all pass — "starting"
#                                    just means inside the healthcheck start_period)
#
# Any failing container gets the tail of its logs dumped, and the script exits
# non-zero so the caller (e2e harness / `./existential.sh test`) can fail.
#
# Usage:
#   container-health.sh <compose-file> [project] [resample-seconds]
#
# Env:
#   DOCKER_CMD       docker binary to use (default: docker)
#   FLAP_THRESHOLD   max tolerated RestartCount for a running container (default: 2)

set -uo pipefail

FILE="${1:?usage: container-health.sh <compose-file> [project] [resample-seconds]}"
PROJECT="${2:-}"
RESAMPLE="${3:-5}"
DOCKER="${DOCKER_CMD:-docker}"
FLAP_THRESHOLD="${FLAP_THRESHOLD:-2}"

SLUG="container-health"
pad() { printf '[%s] %-34s ' "$SLUG" "$1"; }

dc() {
    if [ -n "$PROJECT" ]; then
        "$DOCKER" compose -p "$PROJECT" -f "$FILE" "$@"
    else
        "$DOCKER" compose -f "$FILE" "$@"
    fi
}

printf '\n=== %s (%s) ===\n' "$SLUG" "$(basename "$FILE")"

if [ ! -f "$FILE" ]; then
    echo "[$SLUG] compose file not found: $FILE — nothing to check (skipped)"
    exit 0
fi

mapfile -t IDS < <(dc ps -q 2>/dev/null)
if [ "${#IDS[@]}" -eq 0 ]; then
    echo "[$SLUG] no containers up for this project — nothing to check (skipped)"
    exit 0
fi

# First sample: record each container's RestartCount so we can detect a loop
# that happens to be momentarily 'running' when we look.
declare -A NAME_OF START_COUNT
for id in "${IDS[@]}"; do
    NAME_OF[$id]=$("$DOCKER" inspect -f '{{.Name}}' "$id" 2>/dev/null | sed 's#^/##')
    START_COUNT[$id]=$("$DOCKER" inspect -f '{{.RestartCount}}' "$id" 2>/dev/null || echo 0)
done

# Give an active restart loop time to advance its counter.
sleep "$RESAMPLE"

FAILS=0
for id in "${IDS[@]}"; do
    name="${NAME_OF[$id]}"
    read -r status restarts health < <(
        "$DOCKER" inspect \
            -f '{{.State.Status}} {{.RestartCount}} {{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' \
            "$id" 2>/dev/null || echo "missing 0 none"
    )

    reason=""
    if [ "$status" != "running" ]; then
        reason="status=${status}"
    elif [ "$health" = "unhealthy" ]; then
        reason="health=unhealthy"
    elif [ "$restarts" -gt "${START_COUNT[$id]}" ]; then
        reason="restart-looping (RestartCount ${START_COUNT[$id]}→${restarts})"
    elif [ "$restarts" -ge "$FLAP_THRESHOLD" ]; then
        reason="flapping (RestartCount=${restarts})"
    fi

    if [ -n "$reason" ]; then
        pad "$name"; printf 'FAIL  (%s)\n' "$reason"
        echo "        ---- docker logs --tail 20 ${name} ----"
        "$DOCKER" logs --tail 20 "$id" 2>&1 | sed 's/^/        /' || true
        echo "        ----------------------------------------"
        FAILS=$((FAILS + 1))
    else
        pad "$name"; printf 'OK    (status=%s health=%s restarts=%s)\n' "$status" "$health" "$restarts"
    fi
done

if [ "$FAILS" -gt 0 ]; then
    echo "[$SLUG] ${FAILS} container(s) unhealthy — see logs above"
    exit 1
fi
echo "[$SLUG] all ${#IDS[@]} container(s) in a healthy steady state"
