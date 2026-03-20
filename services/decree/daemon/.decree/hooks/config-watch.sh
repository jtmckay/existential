#!/usr/bin/env bash
# Config Watch Hook
#
# Used as both beforeAll and afterAll. Saves a config hash before
# processing, then compares after. If config changed mid-cycle,
# exits non-zero to restart the daemon and pick up changes.
set -euo pipefail

CONFIG="/work/.decree/config.yml"
HASH_FILE="/tmp/.decree-config-hash"

case "${DECREE_HOOK:-}" in
    beforeAll)
        sha256sum "$CONFIG" | awk '{print $1}' > "$HASH_FILE"
        ;;
    afterAll)
        if [ ! -f "$HASH_FILE" ]; then
            exit 0
        fi
        current=$(sha256sum "$CONFIG" | awk '{print $1}')
        saved=$(cat "$HASH_FILE")
        if [ "$current" != "$saved" ]; then
            echo "Config changed — restarting daemon."
            exit 1
        fi
        ;;
esac
