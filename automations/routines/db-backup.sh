#!/usr/bin/env bash
# DB backup routine
#
# Iterates every entry registered in lib/db-backup-targets.sh and dumps each
# reachable database to a temporary file inside the decree container, then
# rclones the file to EXIST_BACKUP_RCLONE_REMOTE under <tier>/<container>-<ts>.
#
# Tier ("nightly" / "weekly") is the first argument, default "nightly".
# Retention deletes files older than the tier's window after the dump finishes.
#
# Wired up by:
#   automations/cron/db-backup-nightly.md  → tier=nightly, 7-day retention
#   automations/cron/db-backup-weekly.md   → tier=weekly, 28-day retention
#
# Manual invocation:
#   docker exec decree decree run db-backup
#   docker exec decree decree run db-backup -- weekly

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/db-backup-targets.sh
source "${SCRIPT_DIR}/../lib/db-backup-targets.sh"

RCLONE_CONFIG="${RCLONE_CONFIG:-/secrets/rclone/rclone.conf}"
MASTER_ENV="${MASTER_ENV:-/repo/.env}"

# ── Pre-check (decree's startup probe) ────────────────────────────────────────

if [ "${DECREE_PRE_CHECK:-}" = "true" ]; then
    # shellcheck source=../lib/precheck.sh
    source "${SCRIPT_DIR}/../lib/precheck.sh"
    command -v rclone >/dev/null  || precheck_fail "db-backup" "rclone not found"
    command -v pg_dumpall >/dev/null || precheck_fail "db-backup" "pg_dumpall not found"
    command -v mysqldump >/dev/null  || precheck_fail "db-backup" "mysqldump not found"
    command -v mongodump >/dev/null  || precheck_fail "db-backup" "mongodump not found"
    [ -f "$MASTER_ENV" ] || precheck_fail "db-backup" "master .env not mounted at $MASTER_ENV"
    [ -f "$RCLONE_CONFIG" ] || precheck_fail "db-backup" "rclone not configured (run ./existential.sh setup rclone)"
    precheck_pass "db-backup"
    exit 0
fi

TIER="${1:-nightly}"
case "$TIER" in
    nightly) RETENTION_DAYS=7 ;;
    weekly)  RETENTION_DAYS=28 ;;
    *) echo "Unknown tier: $TIER (expected nightly|weekly)" >&2; exit 2 ;;
esac

# Source master .env so DB credential vars are available.
set -a
# shellcheck disable=SC1090
. "$MASTER_ENV"
set +a

REMOTE="${EXIST_BACKUP_RCLONE_REMOTE:-}"
[ -n "$REMOTE" ] || { echo "EXIST_BACKUP_RCLONE_REMOTE is not set — run ./existential.sh setup backup" >&2; exit 1; }

DATE=$(date -u +%Y%m%dT%H%M%SZ)
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

rclone_cmd() { rclone --config "$RCLONE_CONFIG" "$@"; }

# Look up an env var by name, with `_LITERAL_<value>` as an escape hatch for
# fixed strings (e.g., postgres user "librechat" isn't from an env var).
resolve_value() {
    local key="$1"
    if [[ "$key" == _LITERAL_* ]]; then
        printf '%s' "${key#_LITERAL_}"
    else
        printf '%s' "${!key:-}"
    fi
}

container_reachable() { getent hosts "$1" >/dev/null 2>&1; }

dump_postgres() {
    local container="$1" user="$2" password="$3"
    local out="$TMPDIR/${container}-${DATE}.sql.gz"
    PGPASSWORD="$password" pg_dumpall -h "$container" -U "$user" | gzip > "$out"
    echo "$out"
}

dump_mariadb() {
    local container="$1" user="$2" password="$3"
    local out="$TMPDIR/${container}-${DATE}.sql.gz"
    mysqldump -h "$container" -u "$user" -p"$password" --all-databases --single-transaction --quick | gzip > "$out"
    echo "$out"
}

dump_mongo() {
    local container="$1" user="$2" password="$3"
    local out="$TMPDIR/${container}-${DATE}.archive.gz"
    mongodump --uri "mongodb://${user}:${password}@${container}:27017/?authSource=admin" --archive --gzip > "$out"
    echo "$out"
}

# ── Run each registered backup ────────────────────────────────────────────────

dumped=0
skipped=0
failed=0

for entry in "${BACKUP_TARGETS[@]}"; do
    IFS='|' read -r engine container user_key pass_key <<< "$entry"
    if ! container_reachable "$container"; then
        echo "skip   $container (not reachable on exist network)"
        skipped=$((skipped + 1))
        continue
    fi
    user=$(resolve_value "$user_key")
    pass=$(resolve_value "$pass_key")
    if [ -z "$user" ] || [ -z "$pass" ]; then
        echo "skip   $container (credentials missing: $user_key / $pass_key)"
        skipped=$((skipped + 1))
        continue
    fi

    echo "dump   $engine: $container"
    case "$engine" in
        postgres) out=$(dump_postgres "$container" "$user" "$pass") ;;
        mariadb)  out=$(dump_mariadb  "$container" "$user" "$pass") ;;
        mongo)    out=$(dump_mongo    "$container" "$user" "$pass") ;;
        *) echo "  unknown engine: $engine" >&2; failed=$((failed + 1)); continue ;;
    esac

    target="${REMOTE}/${TIER}/${container}/$(basename "$out")"
    if rclone_cmd copyto "$out" "$target"; then
        echo "  → ${target} ($(stat -c %s "$out") bytes)"
        dumped=$((dumped + 1))
    else
        echo "  rclone copy failed for $container" >&2
        failed=$((failed + 1))
    fi
done

# ── Retention ────────────────────────────────────────────────────────────────

echo "prune  ${REMOTE}/${TIER}/ (older than ${RETENTION_DAYS}d)"
rclone_cmd delete --min-age "${RETENTION_DAYS}d" "${REMOTE}/${TIER}/" 2>/dev/null || true
rclone_cmd rmdirs --leave-root "${REMOTE}/${TIER}/" 2>/dev/null || true

echo "done — dumped=${dumped} skipped=${skipped} failed=${failed} tier=${TIER}"
[ "$failed" -eq 0 ]
