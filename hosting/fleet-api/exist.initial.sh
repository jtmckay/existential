#!/usr/bin/env bash
# fleet-api — pre-startup: the host decree project's decree-go-rest config, written once.
#
# .decree/decree-go-rest.yml is this host's (gitignored): each ./existential.sh adds the
# endpoints its host plugins declare (lease_gpu's /gpu/...), so it is never overwritten here.
# The inbox exists before Compose mounts it, so Docker never makes it root-owned.
# Idempotent, no sentinel.
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
rest="${REPO}/.decree/decree-go-rest.yml"
mkdir -p "${REPO}/.decree/inbox"
[[ -f "$rest" ]] && exit 0
cat > "$rest" <<'YML'
# This host's own (gitignored), written once by hosting/fleet-api. The host plugins add their endpoints.
listen: 0.0.0.0:8801 # open to the LAN, plain HTTP: the bearer secret is readable on the wire
secret_env: EXIST_FLEET_SECRET # from .env.shared, the same on every host
decree: decree
daemon:
  enabled: false # the host daemon (existential-host) works the queue
endpoints: []
YML
echo "  wrote .decree/decree-go-rest.yml"
