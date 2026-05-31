#!/usr/bin/env bash
# volume-backup — tar every Docker volume listed in $VOLUMES, rclone the tar
# to `${EXIST_BACKUP_RCLONE_REMOTE}/<tier>/volumes/<volume>/`, prune anything
# older than the tier's retention window.
#
# Triggered by cron files in each service's decree/cron/ dir. Decree exposes
# cron frontmatter keys (TIER, VOLUMES) as env vars. To add or remove a
# volume, edit the cron file's `VOLUMES:` block — and add a matching mount
# line to the service's sidecar in docker-compose.exist.yml.
#
# Manual invocation:
#   docker exec <service>-decree decree run volume-backup
#
# $VOLUMES format (one entry per line, whitespace-separated):
#   <volume_name> <comma,separated,consumer,containers>
# The consumer list is informational at backup time — used by the restore
# flow to know which containers must be stopped before wiping the volume.

set -euo pipefail

RCLONE_CONFIG="${RCLONE_CONFIG:-/secrets/rclone/rclone.conf}"
VOLUMES_ROOT="${VOLUMES_ROOT:-/volumes}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Pre-check ─────────────────────────────────────────────────────────────────

if [ "${DECREE_PRE_CHECK:-}" = "true" ]; then
    # shellcheck source=../lib/precheck.sh
    source "${SCRIPT_DIR}/../lib/precheck.sh"
    command -v rclone >/dev/null || precheck_fail "volume-backup" "rclone not found"
    command -v tar    >/dev/null || precheck_fail "volume-backup" "tar not found"
    [ -f "$RCLONE_CONFIG" ] || precheck_fail "volume-backup" "rclone not configured (run ./existential.sh run rclone)"
    [ -d "$VOLUMES_ROOT" ]  || precheck_fail "volume-backup" "$VOLUMES_ROOT not mounted — add volume mounts to the service sidecar in docker-compose.exist.yml"
    precheck_pass "volume-backup"
    exit 0
fi

# ── Config from cron frontmatter / args ───────────────────────────────────────

TIER="${TIER:-${1:-nightly}}"
case "$TIER" in
    nightly) RETENTION_DAYS=7 ;;
    weekly)  RETENTION_DAYS=28 ;;
    *) echo "Unknown tier: $TIER (expected nightly|weekly)" >&2; exit 2 ;;
esac

[ -n "${VOLUMES:-}" ] || { echo "VOLUMES is empty — set it in the cron frontmatter" >&2; exit 2; }

REMOTE="${EXIST_BACKUP_RCLONE_REMOTE:-}"
[ -n "$REMOTE" ] || { echo "EXIST_BACKUP_RCLONE_REMOTE is not set — run ./existential.sh run backup-config" >&2; exit 1; }

DATE=$(date -u +%Y%m%dT%H%M%SZ)
rclone_cmd() { rclone --config "$RCLONE_CONFIG" "$@"; }

# ── Run each volume from $VOLUMES ────────────────────────────────────────────
# Second column (consumers) is intentionally ignored here — it's used by the
# restore flow, not the backup.

dumped=0
skipped=0
failed=0

while read -r vol _consumers; do
    [ -z "$vol" ] && continue
    [[ "$vol" =~ ^# ]] && continue

    src="${VOLUMES_ROOT}/${vol}"
    if [ ! -d "$src" ]; then
        echo "skip   $vol (not mounted at $src — add a volume mount to the service sidecar in docker-compose.exist.yml)"
        skipped=$((skipped + 1))
        continue
    fi
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
done <<< "$VOLUMES"

# ── Retention ────────────────────────────────────────────────────────────────

echo "prune  ${REMOTE}/${TIER}/volumes/ (older than ${RETENTION_DAYS}d)"
rclone_cmd delete --min-age "${RETENTION_DAYS}d" "${REMOTE}/${TIER}/volumes/" 2>/dev/null || true
rclone_cmd rmdirs --leave-root "${REMOTE}/${TIER}/volumes/" 2>/dev/null || true

echo "done — dumped=${dumped} skipped=${skipped} failed=${failed} tier=${TIER}"
[ "$failed" -eq 0 ]
