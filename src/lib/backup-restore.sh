#!/usr/bin/env bash
# DB / volume backup restore — runs on the host (needs bash + docker only).
#
# DB restores replay a logical dump over a live connection inside the
# service's decree sidecar (which holds the credentials in its environment).
# Volume restores wipe the target volume before extracting — stop consumer
# containers manually before running this script and restart them yourself.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

hr()  { printf '%0.s─' {1..56}; echo; }
die() { echo "Error: $*" >&2; exit 1; }

frontmatter_get() {
    local key="$1" file="$2"
    awk -v k="${key}:" '
        /^---$/ { if (in_fm) exit; in_fm=1; next }
        !in_fm  { next }
        $0 ~ "^" k { found=1; next }
        found && /^[^ ]/  { exit }
        found   { sub(/^  /, ""); print }
    ' "$file"
}

env_get() {
    local key="$1"
    grep -E "^${key}=" "${REPO_DIR}/.env.shared" 2>/dev/null | head -1 | cut -d= -f2-
}

REMOTE=$(env_get "EXIST_BACKUP_RCLONE_REMOTE")
[ -n "$REMOTE" ] || die "EXIST_BACKUP_RCLONE_REMOTE not set — run ./existential.sh run backup-config-config"

DOCKER_CMD="${DOCKER_CMD:-docker}"
command -v "$DOCKER_CMD" >/dev/null 2>&1 || die "${DOCKER_CMD} not found on PATH"

rclone_in() {
    local sidecar="$1"; shift
    $DOCKER_CMD exec "${sidecar}" rclone --config /secrets/rclone/rclone.conf "$@"
}
rclone_lsf() { rclone_in "$1" lsf "${REMOTE}/$2" 2>/dev/null || true; }

# List running *-decree sidecars (excludes the main `decree` daemon).
list_sidecars() {
    $DOCKER_CMD ps --format '{{.Names}}' 2>/dev/null \
        | grep -E '.*-decree$' \
        | grep -v '^decree$' \
        | sort
}

# ── Pick kind and tier ────────────────────────────────────────────────────────

hr
echo "Restore — what kind of backup?"
hr
echo ""
echo "  [1] Database  (logical dump: pg_dumpall / mysqldump / mongodump)"
echo "  [2] Volume    (file-level tar of a Docker volume — destructive)"
echo "  [3] SQLite    (SQL dump — service must be stopped before restore)"
echo ""
read -rp "Kind [1]: " kind
case "${kind:-1}" in
    1|db|database) KIND="db" ;;
    2|vol|volume)  KIND="volume" ;;
    3|sqlite)      KIND="sqlite" ;;
    *) die "Invalid choice." ;;
esac

echo ""
echo "  [1] nightly  (retained 7 days)"
echo "  [2] weekly   (retained 28 days)"
echo ""
read -rp "Tier [1]: " tier
case "${tier:-1}" in
    1|nightly) TIER="nightly" ;;
    2|weekly)  TIER="weekly" ;;
    *) die "Invalid choice." ;;
esac

# ── Pick sidecar ──────────────────────────────────────────────────────────────

echo ""
echo "Running decree sidecars:"
mapfile -t sidecars < <(list_sidecars)
[ ${#sidecars[@]} -gt 0 ] || die "No running *-decree sidecar containers found."
for i in "${!sidecars[@]}"; do echo "  [$((i + 1))] ${sidecars[$i]}"; done
echo ""
read -rp "Sidecar: " pick
[[ "$pick" =~ ^[0-9]+$ ]] || die "Pick a number."
idx=$((pick - 1)); [ "$idx" -ge 0 ] && [ "$idx" -lt "${#sidecars[@]}" ] || die "Out of range."
SIDECAR="${sidecars[$idx]}"

# ── DB restore ────────────────────────────────────────────────────────────────

if [ "$KIND" = "db" ]; then
    CRON_FILE_RAW=$($DOCKER_CMD exec "${SIDECAR}" bash -c \
        "cat /work/.decree/cron/db-backup-${TIER}.md 2>/dev/null || true")
    [ -n "$CRON_FILE_RAW" ] || die "No active db-backup-${TIER} cron in ${SIDECAR} — copy the template from decree/cron.example/ to decree/cron/"

    TARGETS=$(printf '%s\n' "$CRON_FILE_RAW" | awk -v k="TARGETS:" '
        /^---$/ { if (in_fm) exit; in_fm=1; next }
        !in_fm  { next }
        $0 ~ "^" k { found=1; next }
        found && /^[^ ]/  { exit }
        found   { sub(/^  /, ""); print }
    ')
    [ -n "$TARGETS" ] || die "No TARGETS block in ${SIDECAR}'s db-backup-${TIER} cron"

    echo ""
    echo "Services with DB backups in ${REMOTE}/${TIER}/:"
    mapfile -t services < <(rclone_lsf "${SIDECAR}" "${TIER}/" | sed 's:/$::' | grep -v '^volumes$')
    [ ${#services[@]} -gt 0 ] || die "No DB backups at ${REMOTE}/${TIER}/"
    for i in "${!services[@]}"; do echo "  [$((i + 1))] ${services[$i]}"; done
    echo ""
    read -rp "Service: " svc
    [[ "$svc" =~ ^[0-9]+$ ]] || die "Pick a number."
    idx=$((svc - 1)); [ "$idx" -ge 0 ] && [ "$idx" -lt "${#services[@]}" ] || die "Out of range."
    CONTAINER="${services[$idx]}"

    ENGINE="" USER_KEY="" PASS_KEY=""
    while read -r e c u p; do
        [ -z "$e" ] && continue
        if [ "$c" = "$CONTAINER" ]; then
            ENGINE="$e"; USER_KEY="$u"; PASS_KEY="$p"; break
        fi
    done <<< "$TARGETS"
    [ -n "$ENGINE" ] || die "No entry for '$CONTAINER' in ${SIDECAR}'s TARGETS"

    echo ""
    echo "Snapshots:"
    mapfile -t snaps < <(rclone_lsf "${SIDECAR}" "${TIER}/${CONTAINER}/" | sort)
    [ ${#snaps[@]} -gt 0 ] || die "No snapshots for ${CONTAINER}."
    for i in "${!snaps[@]}"; do echo "  [$((i + 1))] ${snaps[$i]}"; done
    echo ""
    read -rp "Snapshot (default: latest): " snap
    if [ -z "$snap" ]; then
        SNAP="${snaps[$((${#snaps[@]} - 1))]}"
    else
        [[ "$snap" =~ ^[0-9]+$ ]] || die "Pick a number."
        i=$((snap - 1)); [ "$i" -ge 0 ] && [ "$i" -lt "${#snaps[@]}" ] || die "Out of range."
        SNAP="${snaps[$i]}"
    fi

    hr
    echo "About to DB-restore:"
    echo "  source   ${REMOTE}/${TIER}/${CONTAINER}/${SNAP}"
    echo "  target   ${CONTAINER}  (engine: ${ENGINE})"
    echo "  sidecar  ${SIDECAR}"
    echo ""
    read -rp "Type the container name (${CONTAINER}) to confirm: " confirm
    [ "$confirm" = "$CONTAINER" ] || { echo "Aborted."; exit 0; }

    echo ""
    echo "Streaming dump into ${CONTAINER}…"
    case "$ENGINE" in
        postgres)
            $DOCKER_CMD exec -i "${SIDECAR}" bash -c "
                set -euo pipefail
                rclone --config /secrets/rclone/rclone.conf cat \
                    \"${REMOTE}/${TIER}/${CONTAINER}/${SNAP}\" \
                | gunzip \
                | PGPASSWORD=\"\${${PASS_KEY}}\" \
                  psql -h ${CONTAINER} -U \"\${${USER_KEY}}\" -d postgres
            "
            ;;
        mariadb)
            $DOCKER_CMD exec -i "${SIDECAR}" bash -c "
                set -euo pipefail
                rclone --config /secrets/rclone/rclone.conf cat \
                    \"${REMOTE}/${TIER}/${CONTAINER}/${SNAP}\" \
                | gunzip \
                | mysql -h ${CONTAINER} -u \"\${${USER_KEY}}\" -p\"\${${PASS_KEY}}\"
            "
            ;;
        mongo)
            $DOCKER_CMD exec -i "${SIDECAR}" bash -c "
                set -euo pipefail
                rclone --config /secrets/rclone/rclone.conf cat \
                    \"${REMOTE}/${TIER}/${CONTAINER}/${SNAP}\" \
                | mongorestore --drop --gzip --archive \
                    --uri \"mongodb://\${${USER_KEY}}:\${${PASS_KEY}}@${CONTAINER}:27017/?authSource=admin\"
            "
            ;;
        *) die "Unknown engine: $ENGINE" ;;
    esac
    echo "Restore complete: ${CONTAINER} ← ${SNAP}"
    exit 0
fi

# ── Volume restore ────────────────────────────────────────────────────────────

if [ "$KIND" = "volume" ]; then

echo ""
echo "Volumes with backups in ${REMOTE}/${TIER}/volumes/:"
mapfile -t vols < <(rclone_lsf "${SIDECAR}" "${TIER}/volumes/" | sed 's:/$::')
[ ${#vols[@]} -gt 0 ] || die "No volume backups at ${REMOTE}/${TIER}/volumes/ (via ${SIDECAR})"
for i in "${!vols[@]}"; do echo "  [$((i + 1))] ${vols[$i]}"; done
echo ""
read -rp "Volume: " vol
[[ "$vol" =~ ^[0-9]+$ ]] || die "Pick a number."
idx=$((vol - 1)); [ "$idx" -ge 0 ] && [ "$idx" -lt "${#vols[@]}" ] || die "Out of range."
VOLUME="${vols[$idx]}"

echo ""
echo "Snapshots:"
mapfile -t snaps < <(rclone_lsf "${SIDECAR}" "${TIER}/volumes/${VOLUME}/" | sort)
[ ${#snaps[@]} -gt 0 ] || die "No snapshots for ${VOLUME}."
for i in "${!snaps[@]}"; do echo "  [$((i + 1))] ${snaps[$i]}"; done
echo ""
read -rp "Snapshot (default: latest): " snap
if [ -z "$snap" ]; then
    SNAP="${snaps[$((${#snaps[@]} - 1))]}"
else
    [[ "$snap" =~ ^[0-9]+$ ]] || die "Pick a number."
    i=$((snap - 1)); [ "$i" -ge 0 ] && [ "$i" -lt "${#snaps[@]}" ] || die "Out of range."
    SNAP="${snaps[$i]}"
fi

hr
echo "About to restore (DESTRUCTIVE):"
echo "  source   ${REMOTE}/${TIER}/volumes/${VOLUME}/${SNAP}"
echo "  target   volume ${VOLUME}"
echo "  sidecar  ${SIDECAR}"
echo ""
echo "  Stop any containers that mount this volume before proceeding."
echo "  Restart them yourself when the restore finishes."
echo ""
read -rp "Type the volume name (${VOLUME}) to proceed: " confirm
[ "$confirm" = "$VOLUME" ] || { echo "Aborted."; exit 0; }

$DOCKER_CMD exec "${SIDECAR}" bash -c "
    set -euo pipefail
    dst=/volumes/${VOLUME}
    [ -d \"\$dst\" ] || { echo 'Volume not mounted at '\$dst' — add it to the sidecar in docker-compose.exist.yml'; exit 1; }
    echo \"Wipe   \$dst\"
    find \"\$dst\" -mindepth 1 -delete
    echo \"Pull   ${REMOTE}/${TIER}/volumes/${VOLUME}/${SNAP}\"
    rclone --config /secrets/rclone/rclone.conf cat \
        \"${REMOTE}/${TIER}/volumes/${VOLUME}/${SNAP}\" \
    | tar xzf - -C \"\$dst\"
"

echo ""
echo "Restore complete: ${VOLUME} ← ${SNAP}"
echo "Restart any containers you stopped before running this."

fi

# ── SQLite restore ────────────────────────────────────────────────────────────

[ "$KIND" = "sqlite" ] || exit 0

CRON_FILE_RAW=$($DOCKER_CMD exec "${SIDECAR}" bash -c \
    "cat /work/.decree/cron/sqlite-backup-${TIER}.md 2>/dev/null || true")
[ -n "$CRON_FILE_RAW" ] || die "No active sqlite-backup-${TIER} cron in ${SIDECAR} — copy the template from decree/cron.example/ to decree/cron/"

TARGETS=$(printf '%s\n' "$CRON_FILE_RAW" | awk -v k="TARGETS:" '
    /^---$/ { if (in_fm) exit; in_fm=1; next }
    !in_fm  { next }
    $0 ~ "^" k { found=1; next }
    found && /^[^ ]/  { exit }
    found   { sub(/^  /, ""); print }
')
[ -n "$TARGETS" ] || die "No TARGETS block in ${SIDECAR}'s sqlite-backup-${TIER} cron"

echo ""
echo "SQLite databases with backups in ${REMOTE}/${TIER}/sqlite/:"
mapfile -t db_names < <(rclone_lsf "${SIDECAR}" "${TIER}/sqlite/" | sed 's:/$::')
[ ${#db_names[@]} -gt 0 ] || die "No SQLite backups at ${REMOTE}/${TIER}/sqlite/ (via ${SIDECAR})"
for i in "${!db_names[@]}"; do echo "  [$((i + 1))] ${db_names[$i]}"; done
echo ""
read -rp "Database: " db
[[ "$db" =~ ^[0-9]+$ ]] || die "Pick a number."
idx=$((db - 1)); [ "$idx" -ge 0 ] && [ "$idx" -lt "${#db_names[@]}" ] || die "Out of range."
DB_NAME="${db_names[$idx]}"

REL_PATH=""
while read -r name rel; do
    [ -z "$name" ] && continue
    if [ "$name" = "$DB_NAME" ]; then REL_PATH="$rel"; break; fi
done <<< "$TARGETS"
[ -n "$REL_PATH" ] || die "No entry for '${DB_NAME}' in ${SIDECAR}'s TARGETS — the backup name and cron TARGETS entry must match"

echo ""
echo "Snapshots:"
mapfile -t snaps < <(rclone_lsf "${SIDECAR}" "${TIER}/sqlite/${DB_NAME}/" | sort)
[ ${#snaps[@]} -gt 0 ] || die "No snapshots for ${DB_NAME}."
for i in "${!snaps[@]}"; do echo "  [$((i + 1))] ${snaps[$i]}"; done
echo ""
read -rp "Snapshot (default: latest): " snap
if [ -z "$snap" ]; then
    SNAP="${snaps[$((${#snaps[@]} - 1))]}"
else
    [[ "$snap" =~ ^[0-9]+$ ]] || die "Pick a number."
    i=$((snap - 1)); [ "$i" -ge 0 ] && [ "$i" -lt "${#snaps[@]}" ] || die "Out of range."
    SNAP="${snaps[$i]}"
fi

hr
echo "About to restore (DESTRUCTIVE):"
echo "  source   ${REMOTE}/${TIER}/sqlite/${DB_NAME}/${SNAP}"
echo "  target   /volumes/${REL_PATH}  (inside ${SIDECAR})"
echo "  sidecar  ${SIDECAR}"
echo ""
echo "  IMPORTANT: stop the service that owns this database before proceeding."
echo "  SQLite restore replaces the live database file — writing to an open"
echo "  database will corrupt it."
echo ""
read -rp "Type the database name (${DB_NAME}) to confirm: " confirm
[ "$confirm" = "$DB_NAME" ] || { echo "Aborted."; exit 0; }

$DOCKER_CMD exec "${SIDECAR}" bash -c "
    set -euo pipefail
    dst=\"/volumes/${REL_PATH}\"
    dir=\"\$(dirname \"\$dst\")\"
    [ -d \"\$dir\" ] || { echo 'Parent directory '\$dir' not found — volume not mounted in sidecar?'; exit 1; }
    echo \"Pull   ${REMOTE}/${TIER}/sqlite/${DB_NAME}/${SNAP}\"
    rclone --config /secrets/rclone/rclone.conf cat \
        \"${REMOTE}/${TIER}/sqlite/${DB_NAME}/${SNAP}\" \
    | gunzip \
    | sqlite3 \"\$dst\"
"

echo ""
echo "Restore complete: ${DB_NAME} ← ${SNAP}"
echo "Restart the service you stopped before running this."
