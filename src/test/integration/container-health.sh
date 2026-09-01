#!/usr/bin/env bash
# container-health.sh — host-side container-state gate.
#
# Runs where docker is visible (the HOST), NOT inside existential-adhoc.
# Per-service exist.test.sh scripts self-elevate into adhoc, which has no
# docker socket and can only reach services over the network — so they
# structurally cannot detect a daemon that is crash-looping or has no HTTP
# surface (decree, decree-backup). This gate fills that gap.
#
# Read-only. Pure observation (docker inspect / docker logs). For every
# container in the given compose project it asserts a healthy steady state:
#   - status == running           (not restarting / exited / dead / created / paused)
#   - not actively restart-looping (RestartCount still advancing across TWO
#                                   consecutive resamples — see below)
#   - not flapping                 (RestartCount below FLAP_THRESHOLD)
#   - Health.Status != unhealthy   (starting / healthy / none all pass — "starting"
#                                    just means inside the healthcheck start_period)
#   - no Docker-managed volume     (every mount is a host bind — see below)
#
# Any failing container gets the tail of its logs dumped, and the script exits
# non-zero so the caller (e2e harness / `./existential.sh test`) can fail.
#
# Usage:
#   container-health.sh <compose-file> [project] [resample-seconds]
#
# One advance is not a loop. Some containers restart themselves exactly once, by
# design, on a cold first boot — homeassistant's entrypoint is the worked example:
# it can only write .storage/http while HA is stopped, so on a boot that began
# with no such file it lets the container exit once and `restart: unless-stopped`
# brings it back fixed. A single-sample check calls that a loop, which is how a
# correct first boot came to fail this gate on every fresh install.
#
# So a container whose count advanced gets a SECOND resample. A real loop keeps
# advancing and still fails; a one-time restart has settled by then and passes,
# with FLAP_THRESHOLD still catching anything that restarted repeatedly before we
# ever looked.
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
declare -A NAME_OF START_COUNT MID_COUNT
for id in "${IDS[@]}"; do
    NAME_OF[$id]=$("$DOCKER" inspect -f '{{.Name}}' "$id" 2>/dev/null | sed 's#^/##')
    START_COUNT[$id]=$("$DOCKER" inspect -f '{{.RestartCount}}' "$id" 2>/dev/null || echo 0)
done

# Give an active restart loop time to advance its counter.
sleep "$RESAMPLE"

_probe() {
    "$DOCKER" inspect \
        -f '{{.State.Status}} {{.RestartCount}} {{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' \
        "$1" 2>/dev/null || echo "missing 0 none"
}

# Containers whose count advanced during the first window. They are not judged
# yet — a second window decides whether the count is still moving.
declare -a RECHECK=()

FAILS=0
declare -A REASON_OF
for id in "${IDS[@]}"; do
    read -r status restarts health < <(_probe "$id")

    reason=""
    if [ "$status" != "running" ]; then
        reason="status=${status}"
    elif [ "$health" = "unhealthy" ]; then
        reason="health=unhealthy"
    elif [ "$restarts" -gt "${START_COUNT[$id]}" ]; then
        # Defer: one advance may be a designed single restart, not a loop.
        RECHECK+=("$id")
        MID_COUNT[$id]="$restarts"
        continue
    elif [ "$restarts" -ge "$FLAP_THRESHOLD" ]; then
        reason="flapping (RestartCount=${restarts})"
    fi
    REASON_OF[$id]="$reason"
done

# Second window, only for the deferred ones.
if [ "${#RECHECK[@]}" -gt 0 ]; then
    sleep "$RESAMPLE"
    for id in "${RECHECK[@]}"; do
        read -r status restarts health < <(_probe "$id")
        reason=""
        if [ "$status" != "running" ]; then
            reason="status=${status}"
        elif [ "$health" = "unhealthy" ]; then
            reason="health=unhealthy"
        elif [ "$restarts" -gt "${MID_COUNT[$id]}" ]; then
            reason="restart-looping (RestartCount ${START_COUNT[$id]}→${MID_COUNT[$id]}→${restarts})"
        elif [ "$restarts" -ge "$FLAP_THRESHOLD" ]; then
            reason="flapping (RestartCount=${restarts})"
        fi
        REASON_OF[$id]="$reason"
    done
fi

for id in "${IDS[@]}"; do
    name="${NAME_OF[$id]}"
    reason="${REASON_OF[$id]}"
    read -r status restarts health < <(_probe "$id")

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

# ── No Docker-managed volumes ────────────────────────────────────────────────
# Only visible from the host, and invisible to every other check: an image with a
# `VOLUME` directive gets an ANONYMOUS volume for any path the template does not
# mount itself. Nothing in the generated compose file mentions it, so
# `validate conventions` cannot see it — but it is opaque, re-inits from the
# image, has the wrong UID on NFS, and leaks a fresh copy on some recreates.
# Nextcloud lost its /var/www/html this way: version.php vanished, the entrypoint
# decided it was a new instance and re-ran the install over a configured one.
for id in "${IDS[@]}"; do
    name="$("$DOCKER" inspect -f '{{.Name}}' "$id" 2>/dev/null | sed 's|^/||')"
    anon="$("$DOCKER" inspect -f '{{range .Mounts}}{{if eq .Type "volume"}}{{.Destination}} {{end}}{{end}}' "$id" 2>/dev/null)"
    [ -z "${anon// }" ] && continue
    pad "$name"; printf 'FAIL  (Docker-managed volume at: %s)\n' "${anon% }"
    echo "        Every volume must be a host bind mount. Add the path to this"
    echo "        service's volumes: and declare it in x-exist-volumes."
    echo "        See .claude/reference/volumes.md."
    FAILS=$((FAILS + 1))
done

if [ "$FAILS" -gt 0 ]; then
    echo "[$SLUG] ${FAILS} container(s) unhealthy — see logs above"
    exit 1
fi
echo "[$SLUG] all ${#IDS[@]} container(s) in a healthy steady state, all volumes host binds"
