#!/usr/bin/env bash
# rclone setup
#
# Interactive configuration of rclone remotes used by decree sync routines
# (Nextcloud, Dropbox, S3, etc.). Add as many remotes as you need — rclone
# handles them all in one session. Run this script again any time to add,
# modify, or remove remotes.
#
# Always runs inside the decree-adhoc container where rclone is installed.
# Config is saved to ${SECRETS_DIR}/rclone/rclone.conf (gitignored).
#
# Run via: ./existential.sh setup rclone
# Or directly in the adhoc container: bash /src/setup/rclone.sh

set -euo pipefail

RCLONE_CONFIG="${SECRETS_DIR:-/secrets}/rclone/rclone.conf"

mkdir -p "$(dirname "$RCLONE_CONFIG")"

# ── Helpers ───────────────────────────────────────────────────────────────────

rclone_run() {
    local tty_flag=()
    if [ "${1:-}" = "-t" ]; then
        tty_flag=(-t)
        shift
    fi
    rclone "${tty_flag[@]}" --config "$RCLONE_CONFIG" "$@"
}

# ── Show existing remotes ─────────────────────────────────────────────────────

mapfile -t existing < <(rclone_run listremotes 2>/dev/null | sed 's/:$//' || true)

if [ ${#existing[@]} -gt 0 ]; then
    echo "Existing remotes:"
    for remote in "${existing[@]}"; do
        echo "  - ${remote}"
    done
else
    echo "No remotes configured yet."
fi

echo ""
echo "Starting rclone config — add as many remotes as you need."
echo "Choose 'q' in the rclone menu when finished."
echo ""

# ── Interactive rclone config ─────────────────────────────────────────────────

rclone_run -t config

# ── Summary ───────────────────────────────────────────────────────────────────

echo ""
mapfile -t configured < <(rclone_run listremotes 2>/dev/null | sed 's/:$//' || true)

if [ ${#configured[@]} -eq 0 ]; then
    echo "No remotes configured."
    exit 1
fi

echo "Configured remotes:"
for remote in "${configured[@]}"; do
    echo "  - ${remote}"
done
echo ""
echo "Config saved to ${RCLONE_CONFIG}"
