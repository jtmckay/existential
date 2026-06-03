#!/usr/bin/env bash
# Apply Docker daemon log rotation settings.
# Copies daemon.json to /etc/docker/daemon.json and reloads the daemon.
# Safe to re-run — no-ops if already applied.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DAEMON_JSON="/etc/docker/daemon.json"
SOURCE="${SCRIPT_DIR}/daemon.json"

if [[ -f "$DAEMON_JSON" ]] && diff -q "$DAEMON_JSON" "$SOURCE" >/dev/null 2>&1; then
    echo "[docker-daemon] daemon.json already up-to-date"
    exit 0
fi

echo "[docker-daemon] Writing ${DAEMON_JSON}..."
sudo install -m 644 "$SOURCE" "$DAEMON_JSON"

echo "[docker-daemon] Reloading Docker daemon (existing containers keep running)..."
sudo systemctl reload docker || sudo kill -HUP "$(pidof dockerd)"

echo "[docker-daemon] Log rotation active: max-size=50m max-file=3"
echo "  Note: only new log entries are rotated — existing oversized logs stay until container restart."
