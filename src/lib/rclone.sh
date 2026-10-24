#!/usr/bin/env bash
# rclone setup
#
# Interactive configuration of rclone remotes used by decree sync routines
# (Nextcloud, Dropbox, S3, etc.), then the backup destination. Add as many
# remotes as you need — rclone handles them all in one session. Run this script
# again any time to add, modify, or remove remotes.
#
# Always runs inside the decree-adhoc container where rclone is installed.
# Config is saved to ${SECRETS_DIR}/rclone/rclone.conf (gitignored).
#
# Run via: ./existential.sh run rclone
# Or directly in the adhoc container: bash /src/lib/rclone.sh

set -euo pipefail

RCLONE_CONFIG="${SECRETS_DIR:-/secrets}/rclone/rclone.conf"

mkdir -p "$(dirname "$RCLONE_CONFIG")"

# ── Helpers ───────────────────────────────────────────────────────────────────

rclone_run() {
    rclone --config "$RCLONE_CONFIG" "$@"
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

rclone_run config

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

# ── Backup destination ────────────────────────────────────────────────────────
#
# EXIST_BACKUP_RCLONE_REMOTE is where every backup routine writes. Set here,
# with the remotes in front of you, rather than by a second command.

EXIST_ENV="${REPO_DIR:-/repo}/.env.shared"
[ -f "$EXIST_ENV" ] || exit 0
current=$(grep -E '^EXIST_BACKUP_RCLONE_REMOTE=' "$EXIST_ENV" | head -1 | cut -d= -f2-)
echo ""
echo "Backups go to EXIST_BACKUP_RCLONE_REMOTE, now: ${current:-not set (nothing is backed up)}."
read -rp "Backup destination as <remote>:<path>, e.g. ${configured[0]}:exist-backups (Enter keeps it): " dest
[ -n "$dest" ] || exit 0
rclone_run mkdir "${dest%/}/" >/dev/null 2>&1 || echo "  ⚠ couldn't create ${dest}; saving anyway"
# .env.shared is the source; the merged .env is what the running routines read.
for f in "$EXIST_ENV" "${REPO_DIR:-/repo}/.env"; do
    [ -f "$f" ] || continue
    if grep -q '^EXIST_BACKUP_RCLONE_REMOTE=' "$f"; then
        awk -v v="$dest" '/^EXIST_BACKUP_RCLONE_REMOTE=/ { print "EXIST_BACKUP_RCLONE_REMOTE=" v; next } 1' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
    else
        echo "EXIST_BACKUP_RCLONE_REMOTE=${dest}" >> "$f"
    fi
done
echo "Saved EXIST_BACKUP_RCLONE_REMOTE=${dest}. Next: pick what to back up (the Backups quest)."
