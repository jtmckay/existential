#!/usr/bin/env bash
# rclone setup
#
# Interactive configuration of rclone remotes used by decree sync routines
# (Nextcloud, Dropbox, S3, etc.). Add as many remotes as you need — rclone
# handles them all in one session. Run this script again any time to add,
# modify, or remove remotes.
#
# Always runs rclone inside the decree container so no host install is needed.
# Config is saved to ${SECRETS_DIR}/rclone/rclone.conf (gitignored).
#
# Normally invoked by setup.sh, which sets SECRETS_DIR.
# Can also be run directly:
#   bash .decree/setup/rclone.sh
#   docker exec -it decree bash /work/.decree/setup/rclone.sh

set -euo pipefail

# ── Container config path (always /config/rclone/rclone.conf inside container) ──

CONTAINER_CONFIG="/config/rclone/rclone.conf"

# ── Helpers ───────────────────────────────────────────────────────────────────

# Run a rclone command — directly if already in the container, via docker exec otherwise.
# Pass -t as first arg to allocate a TTY (required for interactive commands).
rclone_exec() {
    local tty_flag=""
    if [ "${1:-}" = "-t" ]; then
        tty_flag="-it"
        shift
    fi

    if [ "${IN_CONTAINER:-}" = "1" ]; then
        rclone --config "$CONTAINER_CONFIG" "$@"
    else
        # shellcheck disable=SC2086
        docker exec $tty_flag decree rclone --config "$CONTAINER_CONFIG" "$@"
    fi
}

# ── Guard: container must be running when on the host ─────────────────────────

if [ "${IN_CONTAINER:-}" != "1" ]; then
    if ! docker inspect decree >/dev/null 2>&1 || \
       [ "$(docker inspect -f '{{.State.Running}}' decree 2>/dev/null)" != "true" ]; then
        echo "The decree container is not running."
        echo "Start it first: docker compose up -d"
        exit 1
    fi
fi

# ── Show existing remotes ─────────────────────────────────────────────────────

mapfile -t existing < <(rclone_exec listremotes 2>/dev/null | sed 's/:$//' || true)

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

rclone_exec -t config

# ── Summary ───────────────────────────────────────────────────────────────────

echo ""
mapfile -t configured < <(rclone_exec listremotes 2>/dev/null | sed 's/:$//' || true)

if [ ${#configured[@]} -eq 0 ]; then
    echo "No remotes configured."
    exit 1
fi

echo "Configured remotes:"
for remote in "${configured[@]}"; do
    echo "  - ${remote}"
done
echo ""
echo "Config saved to ${CONTAINER_CONFIG}"
