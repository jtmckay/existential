#!/usr/bin/env bash
# Apply Docker daemon log rotation settings.
# MERGES daemon.json into /etc/docker/daemon.json — never overwrites it: an
# nvidia host has its `runtimes.nvidia` block written there by
# `nvidia-ctk runtime configure`, and clobbering that costs the whole
# `docker compose up` (docker refuses a container whose device driver is gone).
# Safe to re-run — no-ops when the settings are already present.
#
# The driver stays json-file on purpose: hosting/loki's alloy tails
# /var/lib/docker/containers/*/*.log and json-parses it, so switching to the
# `local` driver would silently stop shipping container logs to Loki.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DAEMON_JSON="/etc/docker/daemon.json"
SOURCE="${SCRIPT_DIR}/daemon.json"

command -v jq >/dev/null 2>&1 || {
    echo "[docker-daemon] jq is required to merge ${DAEMON_JSON} — install it and re-run." >&2
    exit 1
}

CURRENT="$(sudo cat "$DAEMON_JSON" 2>/dev/null || true)"
[[ -n "${CURRENT//[[:space:]]/}" ]] || CURRENT='{}'
MERGED="$(printf '%s' "$CURRENT" | jq -s --slurpfile new "$SOURCE" '.[0] * $new[0]')"

if [[ "$(printf '%s' "$CURRENT" | jq -S .)" == "$(printf '%s' "$MERGED" | jq -S .)" ]]; then
    echo "[docker-daemon] daemon.json already up-to-date"
    exit 0
fi

TMP="$(mktemp)"; trap 'rm -f "$TMP"' EXIT
printf '%s\n' "$MERGED" >"$TMP"
echo "[docker-daemon] Writing ${DAEMON_JSON}..."
sudo install -m 644 -o root -g root "$TMP" "$DAEMON_JSON"

# log-driver/log-opts are NOT in dockerd's SIGHUP reload set — the daemon has to
# restart, and only containers created after it pick the settings up.
# https://docs.docker.com/engine/logging/configure/
echo "[docker-daemon] Log settings need a daemon restart, which stops and starts every container."
read -rp "  Restart Docker now? (y/N): " answer
if [[ "$answer" =~ ^[Yy]$ ]]; then
    sudo systemctl restart docker
    echo "[docker-daemon] Log rotation active for containers created from now on: max-size=50m max-file=3"
else
    echo "[docker-daemon] Written but not applied. Run: sudo systemctl restart docker"
fi
