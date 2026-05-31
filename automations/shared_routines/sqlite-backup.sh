#!/usr/bin/env bash
# sqlite-backup — dump each SQLite database listed in $TARGETS via sqlite3's
# native .dump mechanism, rclone the compressed SQL to
# `${EXIST_BACKUP_RCLONE_REMOTE}/<tier>/sqlite/<name>/`, prune old backups.
#
# Triggered by cron files in each service's decree/cron/ dir. TARGETS format
# (one entry per line):
#   <name> <path_relative_to_VOLUMES_ROOT>
#   e.g.:  kuma  uptime_kuma_data/kuma.db
#
# Using sqlite3 .dump instead of tar ensures the backup is transaction-
# consistent even while the service is running. Restore by piping the
# decompressed SQL into a fresh sqlite3 database:
#   rclone cat <remote>/<path> | gunzip | sqlite3 restored.db
#
# Manual invocation:
#   docker exec <service>-decree decree run sqlite-backup

set -euo pipefail

RCLONE_CONFIG="${RCLONE_CONFIG:-/secrets/rclone/rclone.conf}"
VOLUMES_ROOT="${VOLUMES_ROOT:-/volumes}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Pre-check ─────────────────────────────────────────────────────────────────

if [ "${DECREE_PRE_CHECK:-}" = "true" ]; then
    # shellcheck source=../lib/precheck.sh
    source "${SCRIPT_DIR}/../lib/precheck.sh"
    command -v rclone  >/dev/null || precheck_fail "sqlite-backup" "rclone not found"
    command -v sqlite3 >/dev/null || precheck_fail "sqlite-backup" "sqlite3 not found"
    [ -f "$RCLONE_CONFIG" ] || precheck_fail "sqlite-backup" "rclone not configured (run ./existential.sh run rclone)"
    precheck_pass "sqlite-backup"
    exit 0
fi

# ── Config from cron frontmatter / args ───────────────────────────────────────

TIER="${TIER:-${1:-nightly}}"
case "$TIER" in
    nightly) RETENTION_DAYS=7 ;;
    weekly)  RETENTION_DAYS=28 ;;
    *) echo "Unknown tier: $TIER (expected nightly|weekly)" >&2; exit 2 ;;
esac

[ -n "${TARGETS:-}" ] || { echo "TARGETS is empty — set it in the cron frontmatter" >&2; exit 2; }

REMOTE="${EXIST_BACKUP_RCLONE_REMOTE:-}"
[ -n "$REMOTE" ] || { echo "EXIST_BACKUP_RCLONE_REMOTE is not set — run ./existential.sh run backup-config" >&2; exit 1; }

DATE=$(date -u +%Y%m%dT%H%M%SZ)
rclone_cmd() { rclone --config "$RCLONE_CONFIG" "$@"; }

# ── Dump each database ────────────────────────────────────────────────────────

dumped=0
skipped=0
failed=0

while read -r name rel_path; do
    [ -z "$name" ] && continue
    [[ "$name" =~ ^# ]] && continue

    db_file="${VOLUMES_ROOT}/${rel_path}"
    if [ ! -f "$db_file" ]; then
        echo "skip   $name (not found at $db_file)"
        skipped=$((skipped + 1))
        continue
    fi

    target="${REMOTE}/${TIER}/sqlite/${name}/${name}-${DATE}.sql.gz"
    echo "dump   $name → $target"
    if sqlite3 "$db_file" ".dump" | gzip | rclone_cmd rcat "$target"; then
        dumped=$((dumped + 1))
    else
        echo "  failed" >&2
        failed=$((failed + 1))
    fi
done <<< "$TARGETS"

# ── Retention ─────────────────────────────────────────────────────────────────

echo "prune  ${REMOTE}/${TIER}/sqlite/ (older than ${RETENTION_DAYS}d)"
rclone_cmd delete --min-age "${RETENTION_DAYS}d" "${REMOTE}/${TIER}/sqlite/" 2>/dev/null || true
rclone_cmd rmdirs --leave-root "${REMOTE}/${TIER}/sqlite/" 2>/dev/null || true

echo "done — dumped=${dumped} skipped=${skipped} failed=${failed} tier=${TIER}"
[ "$failed" -eq 0 ]
