#!/usr/bin/env bash
# backup-runner.sh — entrypoint of the existential-backup container.
#
# All destructive / network-touching work happens here. The host-side wrapper
# (./existential.sh backup …) handles pre-checks (running consumer detection,
# stop/restart) and then `docker compose run`s this container.
#
# Modes:
#   backup <tier>              tar each /volumes/<name>, rclone rcat to remote
#   restore <volume> <path>    rclone cat <path>, wipe /volumes/<volume>, untar
#   list <prefix>              rclone lsf the given prefix (for restore UI)
#   list-targets               echo every registered volume name (for UI)

set -euo pipefail

MODE="${1:?mode required: backup | restore | list | list-targets}"
shift

VOLUMES_ROOT="/volumes"
RCLONE_CONFIG="/secrets/rclone/rclone.conf"
MASTER_ENV="/repo/.env"

# Registry lives under /work/.decree/lib (decree's working dir mount).
# shellcheck source=../automations/lib/volume-backup-targets.sh
source /work/.decree/lib/volume-backup-targets.sh

rclone_cmd() {
    [ -f "$RCLONE_CONFIG" ] || { echo "rclone not configured" >&2; exit 1; }
    rclone --config "$RCLONE_CONFIG" "$@"
}

load_remote() {
    [ -f "$MASTER_ENV" ] || { echo "${MASTER_ENV} not found" >&2; exit 1; }
    set -a
    # shellcheck disable=SC1090
    . "$MASTER_ENV"
    set +a
    [ -n "${EXIST_BACKUP_RCLONE_REMOTE:-}" ] || {
        echo "EXIST_BACKUP_RCLONE_REMOTE is not set — run ./existential.sh setup backup" >&2
        exit 1
    }
    REMOTE="$EXIST_BACKUP_RCLONE_REMOTE"
}

case "$MODE" in
    list-targets)
        backup_targets_volumes
        ;;

    list)
        load_remote
        prefix="${1:-}"
        rclone_cmd lsf "${REMOTE}/${prefix}" 2>/dev/null || true
        ;;

    backup)
        load_remote
        TIER="${1:-nightly}"
        case "$TIER" in
            nightly) RETENTION_DAYS=7 ;;
            weekly)  RETENTION_DAYS=28 ;;
            *) echo "Unknown tier: $TIER (expected nightly|weekly)" >&2; exit 2 ;;
        esac
        DATE=$(date -u +%Y%m%dT%H%M%SZ)
        dumped=0 skipped=0 failed=0
        while IFS= read -r vol; do
            src="${VOLUMES_ROOT}/${vol}"
            if [ ! -d "$src" ]; then
                echo "skip   $vol (not mounted)"
                skipped=$((skipped + 1))
                continue
            fi
            # If the volume directory is empty, the tar is essentially empty —
            # still worth a record so retention can prune it, but flag it.
            if [ -z "$(ls -A "$src" 2>/dev/null)" ]; then
                echo "warn   $vol is empty"
            fi
            target="${REMOTE}/${TIER}/volumes/${vol}/${vol}-${DATE}.tar.gz"
            echo "tar    $vol → $target"
            if tar czf - -C "$src" . 2>/dev/null | rclone_cmd rcat "$target"; then
                dumped=$((dumped + 1))
            else
                echo "  failed" >&2
                failed=$((failed + 1))
            fi
        done < <(backup_targets_volumes)
        echo "prune  ${REMOTE}/${TIER}/volumes/ older than ${RETENTION_DAYS}d"
        rclone_cmd delete --min-age "${RETENTION_DAYS}d" "${REMOTE}/${TIER}/volumes/" 2>/dev/null || true
        rclone_cmd rmdirs --leave-root "${REMOTE}/${TIER}/volumes/" 2>/dev/null || true
        echo "done — dumped=${dumped} skipped=${skipped} failed=${failed} tier=${TIER}"
        [ "$failed" -eq 0 ]
        ;;

    restore)
        load_remote
        VOLUME="${1:?volume name required}"
        SNAPSHOT_PATH="${2:?snapshot rclone path required (e.g. nightly/volumes/<vol>/<file>.tar.gz)}"
        dst="${VOLUMES_ROOT}/${VOLUME}"
        if [ ! -d "$dst" ]; then
            echo "Volume not mounted at ${dst} — add it to existential-compose.yml" >&2
            exit 1
        fi
        echo "Wipe   $dst"
        find "$dst" -mindepth 1 -delete
        echo "Pull   ${REMOTE}/${SNAPSHOT_PATH}"
        rclone_cmd cat "${REMOTE}/${SNAPSHOT_PATH}" | tar xzf - -C "$dst"
        echo "Restore complete: ${VOLUME} ← ${SNAPSHOT_PATH}"
        ;;

    *)
        echo "Unknown mode: $MODE" >&2
        exit 2
        ;;
esac
