#!/usr/bin/env bash
# DB / volume backup restore — runs ON THE HOST.
#
# DB restores can be done while the database is running (the restore is a
# logical replay over a live connection). Volume restores cannot: the target
# volume is wiped and re-extracted, so any container with the volume mounted
# would see files disappear out from under open handles. This script enforces
# the difference by querying docker for running consumers before kicking off
# a volume restore.
#
# All rclone work (listing snapshots, streaming the dump back) is delegated
# to the existential-backup adhoc container; the host script only orchestrates.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
COMPOSE_FILE="${REPO_DIR}/existential-compose.yml"
MASTER_COMPOSE="${REPO_DIR}/docker-compose.yml"

hr() { printf '%0.s─' {1..56}; echo; }
die() { echo "Error: $*" >&2; exit 1; }

env_get() {
    local file="$1" key="$2"
    grep -E "^${key}=" "$file" 2>/dev/null | head -1 | cut -d= -f2-
}

REMOTE=$(env_get "${REPO_DIR}/.env.exist" "EXIST_BACKUP_RCLONE_REMOTE")
[ -n "$REMOTE" ] || die "EXIST_BACKUP_RCLONE_REMOTE not set — run ./existential.sh setup backup"

DOCKER_CMD="${DOCKER_CMD:-docker}"
command -v "$DOCKER_CMD" >/dev/null 2>&1 || die "${DOCKER_CMD} not found on PATH"

# Helper that runs the backup container with a sub-command.
backup_run() {
    $DOCKER_CMD compose -f "$COMPOSE_FILE" --profile backup run --rm \
        existential-backup "$@"
}

# ── Pick a restore kind ───────────────────────────────────────────────────────

hr
echo "Restore — what kind of backup?"
hr
echo ""
echo "  [1] Database  (logical dump: pg_dumpall / mysqldump / mongodump)"
echo "  [2] Volume    (file-level tar of a Docker volume — destructive)"
echo ""
read -rp "Kind [1]: " kind
case "${kind:-1}" in
    1|db|database) KIND="db" ;;
    2|vol|volume)  KIND="volume" ;;
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

# ── DB restore ────────────────────────────────────────────────────────────────

if [ "$KIND" = "db" ]; then
    # shellcheck source=../../automations/lib/db-backup-targets.sh
    source "${REPO_DIR}/automations/lib/db-backup-targets.sh"

    echo ""
    echo "Services with DB backups in ${REMOTE}/${TIER}/:"
    mapfile -t services < <(backup_run list "${TIER}/" 2>/dev/null \
        | sed 's:/$::' | grep -v '^volumes$')
    [ ${#services[@]} -gt 0 ] || die "No DB backups at ${REMOTE}/${TIER}/"
    for i in "${!services[@]}"; do echo "  [$((i + 1))] ${services[$i]}"; done
    echo ""
    read -rp "Service: " svc
    [[ "$svc" =~ ^[0-9]+$ ]] || die "Pick a number."
    idx=$((svc - 1)); [ "$idx" -ge 0 ] && [ "$idx" -lt "${#services[@]}" ] || die "Out of range."
    CONTAINER="${services[$idx]}"

    ENGINE="" USER_KEY="" PASS_KEY=""
    for entry in "${BACKUP_TARGETS[@]}"; do
        IFS='|' read -r e c u p <<< "$entry"
        if [ "$c" = "$CONTAINER" ]; then
            ENGINE="$e"; USER_KEY="$u"; PASS_KEY="$p"; break
        fi
    done
    [ -n "$ENGINE" ] || die "No registry entry for '$CONTAINER'"

    echo ""
    echo "Snapshots:"
    mapfile -t snaps < <(backup_run list "${TIER}/${CONTAINER}/" 2>/dev/null | sort)
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
    echo "  source     ${REMOTE}/${TIER}/${CONTAINER}/${SNAP}"
    echo "  target     ${CONTAINER}  (engine: ${ENGINE})"
    echo ""
    read -rp "Type the container name (${CONTAINER}) to confirm: " confirm
    [ "$confirm" = "$CONTAINER" ] || { echo "Aborted."; exit 0; }

    # The DB restore is short enough to drive from decree-backup, which has
    # the client tools + the master .env mount (main decree intentionally
    # does not). Pipe the rclone-fetched dump in.
    echo ""
    echo "Streaming dump into ${CONTAINER}…"
    case "$ENGINE" in
        postgres)
            $DOCKER_CMD exec -i decree-backup bash -c "
                set -euo pipefail
                . /repo/.env
                source /work/.decree/lib/db-backup-targets.sh
                rclone --config /secrets/rclone/rclone.conf cat \
                    \"\${EXIST_BACKUP_RCLONE_REMOTE}/${TIER}/${CONTAINER}/${SNAP}\" \
                | gunzip \
                | PGPASSWORD=\"\${${PASS_KEY#_LITERAL_}:-${PASS_KEY#_LITERAL_}}\" \
                  psql -h ${CONTAINER} -U ${USER_KEY#_LITERAL_} -d postgres
            "
            ;;
        mariadb)
            $DOCKER_CMD exec -i decree-backup bash -c "
                set -euo pipefail
                . /repo/.env
                rclone --config /secrets/rclone/rclone.conf cat \
                    \"\${EXIST_BACKUP_RCLONE_REMOTE}/${TIER}/${CONTAINER}/${SNAP}\" \
                | gunzip \
                | mysql -h ${CONTAINER} -u ${USER_KEY#_LITERAL_} -p\"\${${PASS_KEY}}\"
            "
            ;;
        mongo)
            $DOCKER_CMD exec -i decree-backup bash -c "
                set -euo pipefail
                . /repo/.env
                rclone --config /secrets/rclone/rclone.conf cat \
                    \"\${EXIST_BACKUP_RCLONE_REMOTE}/${TIER}/${CONTAINER}/${SNAP}\" \
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

# shellcheck source=../../automations/lib/volume-backup-targets.sh
source "${REPO_DIR}/automations/lib/volume-backup-targets.sh"

echo ""
echo "Volumes with backups in ${REMOTE}/${TIER}/volumes/:"
mapfile -t vols < <(backup_run list "${TIER}/volumes/" 2>/dev/null | sed 's:/$::')
[ ${#vols[@]} -gt 0 ] || die "No volume backups at ${REMOTE}/${TIER}/volumes/"
for i in "${!vols[@]}"; do echo "  [$((i + 1))] ${vols[$i]}"; done
echo ""
read -rp "Volume: " vol
[[ "$vol" =~ ^[0-9]+$ ]] || die "Pick a number."
idx=$((vol - 1)); [ "$idx" -ge 0 ] && [ "$idx" -lt "${#vols[@]}" ] || die "Out of range."
VOLUME="${vols[$idx]}"

echo ""
echo "Snapshots:"
mapfile -t snaps < <(backup_run list "${TIER}/volumes/${VOLUME}/" 2>/dev/null | sort)
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

# ── Pre-check: consumer containers must NOT be running ───────────────────────

mapfile -t CONSUMERS < <(backup_targets_consumers "$VOLUME")
[ ${#CONSUMERS[@]} -gt 0 ] || die "Volume '$VOLUME' has no consumers registered in volume-backup-targets.sh"

RUNNING=()
for c in "${CONSUMERS[@]}"; do
    if $DOCKER_CMD ps --filter "name=^${c}$" --format '{{.Names}}' | grep -qx "$c"; then
        RUNNING+=("$c")
    fi
done

hr
echo "About to restore (DESTRUCTIVE):"
echo "  source     ${REMOTE}/${TIER}/volumes/${VOLUME}/${SNAP}"
echo "  target     volume ${VOLUME}"
echo "  consumers  ${CONSUMERS[*]}"
echo ""

STOPPED=()
if [ ${#RUNNING[@]} -gt 0 ]; then
    echo "⚠ These consumer containers are currently running:"
    for c in "${RUNNING[@]}"; do echo "    - $c"; done
    echo ""
    echo "  Restore wipes the volume before extracting. Any process with"
    echo "  open files on the volume will read garbage. Stop them now?"
    echo ""
    read -rp "Stop ${RUNNING[*]} and continue? (y/N): " ans
    if [[ "${ans,,}" != "y" ]]; then
        echo "Aborted (containers still running)."
        exit 0
    fi
    echo "Stopping…"
    $DOCKER_CMD stop "${RUNNING[@]}"
    STOPPED=("${RUNNING[@]}")
fi

read -rp "Type the volume name (${VOLUME}) to proceed: " confirm
if [ "$confirm" != "$VOLUME" ]; then
    echo "Aborted."
    # Restart anything we stopped so we don't leave the user worse off.
    if [ ${#STOPPED[@]} -gt 0 ]; then
        echo "Restarting ${STOPPED[*]}…"
        $DOCKER_CMD start "${STOPPED[@]}" >/dev/null
    fi
    exit 0
fi

# ── Run the restore ──────────────────────────────────────────────────────────

backup_run restore "$VOLUME" "${TIER}/volumes/${VOLUME}/${SNAP}"

# ── Restart consumers we stopped ─────────────────────────────────────────────

if [ ${#STOPPED[@]} -gt 0 ]; then
    echo ""
    echo "Restarting ${STOPPED[*]}…"
    $DOCKER_CMD start "${STOPPED[@]}" >/dev/null
fi

echo ""
echo "Restore complete: ${VOLUME} ← ${SNAP}"
