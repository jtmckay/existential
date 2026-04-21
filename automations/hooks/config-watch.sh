#!/usr/bin/env bash
set -euo pipefail

CONFIG="/work/.decree/config.yml"
HASH_FILE="/work/.decree/config.hash"

hash_config() {
    sha256sum "$CONFIG" | awk '{print $1}'
}

current="$(hash_config)"

if [ ! -f "$HASH_FILE" ]; then
    printf '%s\n' "$current" > "$HASH_FILE"
    exit 0
fi

saved="$(cat "$HASH_FILE")"

if [ "$current" != "$saved" ]; then
    printf '%s\n' "$current" > "$HASH_FILE"
    echo "Config changed — terminating container main process for restart."
    kill -TERM 1
    sleep 2
    kill -KILL 1 2>/dev/null || true
fi