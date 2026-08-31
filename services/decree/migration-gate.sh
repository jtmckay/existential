#!/usr/bin/env bash
# migration-gate.sh — the health gate the decree daemon waits on before it runs
# `decree process`.
#
# The decree image entrypoint (automations/entrypoint.sh) retries
# /work/exist.test.sh every 10s, up to DECREE_MIGRATE_TIMEOUT, and only then
# runs migrations. For a per-service sidecar that file was the service's own
# exist.test.sh. This daemon's migrations target OTHER services — ollama's model
# pulls, minio's buckets and service account — so its gate is a probe of each of
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

# minio — migrations 20-22 create buckets and the nextcloud service account.
gate nas/minio "http://minio:9000/minio/health/live" minio

exit "$fail"
