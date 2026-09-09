#!/usr/bin/env bash
# migration-gate.sh — the health gate the decree daemon waits on before it runs
# `decree process`.
#
# The decree image entrypoint (services/automation/decree/entrypoint.sh) retries
# /work/exist.test.sh every 10s, up to DECREE_MIGRATE_TIMEOUT, and only then
# runs migrations. For a per-service sidecar that file was the service's own
# exist.test.sh. This daemon's migrations target OTHER services — ollama's model
# pulls, home assistant's onboarding — so its gate is a probe of each of
# those, and a service that is disabled is simply not waited for.
#
# Read-only, no writes anywhere. Exits 0 once every enabled target answers.
#
# Mounted at /work/exist.test.sh; the repo is at /repo, read-only.

set -uo pipefail

REPO_DIR="${REPO_DIR:-/repo}"
# service-common.sh reads enablement relative to $SCRIPT_DIR at call time.
# shellcheck disable=SC2034  # read by service-common.sh, not by this file
SCRIPT_DIR="$REPO_DIR"

# shellcheck source=../../src/utils/service-common.sh
. "${REPO_DIR}/src/utils/service-common.sh"

fail=0

# Probe one URL, but only when its service is enabled.
gate() {
    local dir="$1" url="$2" name="$3"
    service_is_enabled "${REPO_DIR}/${dir}" || return 0
    if curl -fsS --max-time 5 -o /dev/null "$url"; then
        return 0
    fi
    echo "[migration-gate] ${name} not ready (${url})" >&2
    fail=1
}

# ollama — migrations 10-14 pull models through this API.
gate ai/ollama "${EXIST_OLLAMA_URL:-http://ollama:11434}/api/tags" ollama

# homeassistant — migrations 25/26 complete onboarding and wire wyoming/hermes
# through its HTTP/websocket API. On a truly fresh volume (no .storage/http
# yet), services/homeassistant/entrypoint.sh guarantees HA restarts itself
# exactly once, ~9-10s after first boot (.storage/http appears ~4-5s in, then
# a further 5s wait), to promote that file's "pending" proxy settings to
# "stable". /manifest.json answers before that restart happens (it's a static
# asset, served while HA is still starting up), so probing it alone would
# pass the gate and let migrations start right before HA cuts its own
# connections out from under them — exactly the empty-reply/
# connection-refused failures a fresh reset produces.
#
# Can't read the file's own settled/pending state to wait it out properly:
# HA runs as root with no PUID/PGID support (see docker-compose.exist.yml),
# so .storage/http is root-owned mode 600 and this container's non-root user
# gets EACCES on its contents. Its parent dir is world-readable+executable
# though, so `stat` (existence + mtime, gated by directory permissions, not
# the file's own) still works — use the file's age as a proxy for "past the
# restart window" instead of reading what's inside it.
gate_homeassistant() {
    local dir="services/homeassistant" url="${HOMEASSISTANT_URL:-http://homeassistant:8123}/manifest.json"
    service_is_enabled "${REPO_DIR}/${dir}" || return 0
    if ! curl -fsS --max-time 5 -o /dev/null "$url"; then
        echo "[migration-gate] homeassistant not ready (${url})" >&2
        fail=1
        return
    fi
    local store="${REPO_DIR}/volumes/homeassistant_data/.storage/http"
    local mtime age
    mtime=$(stat -c '%Y' "$store" 2>/dev/null) || mtime=0
    age=$(( $(date +%s) - mtime ))
    # 20s: comfortable margin past the ~9-10s decision point plus the restart
    # itself. mtime==0 (file doesn't exist yet) always fails this.
    if (( mtime == 0 || age < 20 )); then
        echo "[migration-gate] homeassistant not ready (within its own post-install restart window)" >&2
        fail=1
    fi
}
gate_homeassistant

exit "$fail"
