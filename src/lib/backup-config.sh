#!/usr/bin/env bash
# DB backup setup
#
# Configures EXIST_BACKUP_RCLONE_REMOTE in the root .env.shared — the
# destination the db-backup routine writes to. Any rclone remote works
# (minio:exist-backups, dropbox:Existential/Backups, b2:my-bucket/db, …).
#
# Prerequisite: rclone has at least one remote configured. If not, this
# script offers to run `./existential.sh run rclone` first.
#
# Run via: ./existential.sh run backup-config

set -euo pipefail

REPO_DIR="${REPO_DIR:-/repo}"
EXIST_ENV="${REPO_DIR}/.env.shared"
RCLONE_CONFIG="${SECRETS_DIR:-/secrets}/rclone/rclone.conf"

hr() { printf '%0.s─' {1..56}; echo; }
die() { echo "Error: $*" >&2; exit 1; }

env_get() {
    local file="$1" key="$2"
    grep -E "^${key}=" "$file" 2>/dev/null | head -1 | cut -d= -f2-
}

env_set() {
    local file="$1" key="$2" value="$3"
    if grep -qE "^${key}=" "$file" 2>/dev/null; then
        sed -i "s|^${key}=.*|${key}=${value}|" "$file"
    else
        echo "${key}=${value}" >> "$file"
    fi
}

[ -f "$EXIST_ENV" ] || die "${EXIST_ENV} not found — run ./existential.sh first"

# ── List configured rclone remotes ────────────────────────────────────────────

if [ ! -f "$RCLONE_CONFIG" ]; then
    echo "No rclone remotes configured yet."
    echo "Run ./existential.sh run rclone first, then re-run setup backup."
    exit 1
fi

mapfile -t remotes < <(rclone --config "$RCLONE_CONFIG" listremotes 2>/dev/null | sed 's/:$//' || true)

if [ ${#remotes[@]} -eq 0 ]; then
    echo "rclone config exists but has no remotes. Run ./existential.sh run rclone first."
    exit 1
fi

current=$(env_get "$EXIST_ENV" "EXIST_BACKUP_RCLONE_REMOTE")

hr
echo "DB backup destination"
hr
echo ""
echo "Configured rclone remotes:"
for r in "${remotes[@]}"; do
    echo "  - ${r}"
done
echo ""
if [ -n "$current" ]; then
    echo "Current: ${current}"
else
    echo "Current: (not set)"
fi
echo ""
echo "Enter the backup destination as <remote>:<path>"
echo "  e.g. minio:exist-backups"
echo "       dropbox:Existential/Backups"
echo "       b2:my-bucket/db"
echo ""
read -rp "Destination [${current}]: " input
DEST="${input:-$current}"
[ -n "$DEST" ] || die "Destination is required."

# ── Smoke test the remote ─────────────────────────────────────────────────────

echo ""
echo "Probing ${DEST}…"
if rclone --config "$RCLONE_CONFIG" lsd "${DEST%/}/" >/dev/null 2>&1 \
        || rclone --config "$RCLONE_CONFIG" mkdir "${DEST%/}/" >/dev/null 2>&1; then
    echo "  ✓ reachable / created"
else
    echo "  ⚠ couldn't list or create at ${DEST}"
    read -rp "  Save anyway? (y/N): " confirm
    [[ "${confirm,,}" == "y" ]] || { echo "Aborted."; exit 0; }
fi

# ── Persist ───────────────────────────────────────────────────────────────────

env_set "$EXIST_ENV" "EXIST_BACKUP_RCLONE_REMOTE" "$DEST"
echo ""
echo "Updated ${EXIST_ENV}: EXIST_BACKUP_RCLONE_REMOTE=${DEST}"

# Also push into the running master .env so the routine sees it without a
# full ./existential.sh compose round-trip.
if [ -f "${REPO_DIR}/.env" ]; then
    env_set "${REPO_DIR}/.env" "EXIST_BACKUP_RCLONE_REMOTE" "$DEST"
fi

hr
echo ""
echo "DB backups (logical dumps) and volume backups run inside per-service"
echo "decree sidecars on their own cron schedules."
echo ""
echo "Each backup-eligible service ships cron templates at:"
echo "  <category>/<service>/decree/cron.example/"
echo ""
echo "Activate by copying the templates you want into the service's cron/ dir:"
echo "  cp <service>/decree/cron.example/<name>.md <service>/decree/cron/"
echo "  docker compose restart <service>-decree"
echo ""
echo "Defaults:"
echo "  db-backup-nightly       02:00 UTC daily,  retained  7d  (${DEST}/nightly/<container>/)"
echo "  db-backup-weekly        03:00 UTC Sun,    retained 28d  (${DEST}/weekly/<container>/)"
echo "  volume-backup-nightly   02:30 UTC daily,  retained  7d  (${DEST}/nightly/volumes/<vol>/)"
echo "  volume-backup-weekly    03:30 UTC Sun,    retained 28d  (${DEST}/weekly/volumes/<vol>/)"
echo ""
echo "Edit the TARGETS / VOLUMES blocks in each cron file to configure targets."
echo ""
echo "Run a backup right now:"
echo "  ./existential.sh backup db       [nightly|weekly]"
echo "  ./existential.sh backup volumes  [nightly|weekly]"
echo "  ./existential.sh backup restore  (interactive — DB or volume)"
