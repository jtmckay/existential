#!/usr/bin/env bash
# db_backup — dump every database listed in $TARGETS, rclone the dumps to
# `${EXIST_BACKUP_RCLONE_REMOTE}/<tier>/<container>/`, prune anything older
# than the tier's retention window.
#
# Triggered by cron files in services/automation/backup/cron/, whose params
# (TIER, TARGETS) are this machine's data. Credential vars
# come from automation-backup's environment, which is the master .env.
#
# Manual invocation:
#   docker exec automation-backup decree emit --machine db_backup \
#       --param TIER=nightly --param TARGETS="..." </dev/null
#
# $TARGETS format (one entry per line, whitespace-separated):
#   <engine> <container> <USER_ENV_VAR> <PASS_ENV_VAR>
# Use `_LITERAL_<value>` for a fixed username (e.g. `_LITERAL_root`).
# Engines: postgres | mariadb | mongo.

set -euo pipefail

RCLONE_CONFIG="${RCLONE_CONFIG:-/secrets/rclone/rclone.conf}"

[ -f "$RCLONE_CONFIG" ] || { echo "rclone not configured (run ./existential.sh run rclone)" >&2; exit 1; }

# ── Config from the cron file's params ───────────────────────────────────────

TIER="$DECREE_DATA_TIER"
TARGETS="$DECREE_DATA_TARGETS"
case "$TIER" in
    nightly) RETENTION_DAYS=7 ;;
    weekly)  RETENTION_DAYS=28 ;;
    *) echo "Unknown tier: $TIER (expected nightly|weekly)" >&2; exit 2 ;;
esac

[ -n "$TARGETS" ] || { echo "TARGETS is empty — set it in the cron file's params" >&2; exit 2; }

REMOTE="${EXIST_BACKUP_RCLONE_REMOTE:-}"
[ -n "$REMOTE" ] || { echo "EXIST_BACKUP_RCLONE_REMOTE is not set — run ./existential.sh run backup-config" >&2; exit 1; }

DATE=$(date -u +%Y%m%dT%H%M%SZ)
TMPDIR=$(mktemp -d "${DECREE_RUN_DIR:-/tmp}/tmp.XXXXXX")
trap 'rm -rf "$TMPDIR"' EXIT

rclone_cmd() { rclone --config "$RCLONE_CONFIG" "$@"; }

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
    # Pass the password via MYSQL_PWD, not -p"$password", so it never appears in
    # the container's process list (matches PGPASSWORD usage in dump_postgres).
    MYSQL_PWD="$password" mysqldump -h "$container" -u "$user" --all-databases --single-transaction --quick | gzip > "$out"
    echo "$out"
}

dump_mongo() {
    local container="$1" user="$2" password="$3"
    local out="$TMPDIR/${container}-${DATE}.archive.gz"
    mongodump --uri "mongodb://${user}:${password}@${container}:27017/?authSource=admin" --archive --gzip > "$out"
    echo "$out"
}

# ── Run each target from $TARGETS ─────────────────────────────────────────────

dumped=0
skipped=0
failed=0

while read -r engine container user_key pass_key; do
    [ -z "$engine" ] && continue
    [[ "$engine" =~ ^# ]] && continue

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
done <<< "$TARGETS"

# ── Retention ────────────────────────────────────────────────────────────────

echo "prune  ${REMOTE}/${TIER}/ (older than ${RETENTION_DAYS}d)"
if ! rclone_cmd delete --min-age "${RETENTION_DAYS}d" "${REMOTE}/${TIER}/"; then
    echo "  warn: retention cleanup (delete) failed — old backups may accumulate" >&2
fi
if ! rclone_cmd rmdirs --leave-root "${REMOTE}/${TIER}/"; then
    echo "  warn: retention cleanup (rmdirs) failed" >&2
fi

echo "done — dumped=${dumped} skipped=${skipped} failed=${failed} tier=${TIER}"
[ "$failed" -eq 0 ]
