#!/usr/bin/env bash
# Vikunja — first-time setup
#
# Creates the default Vikunja user from VIKUNJA_DEFAULT_{USERNAME,PASSWORD,EMAIL}
# (set in services/vikunja/.env).
#
# Auto-run by `./existential.sh` once when EXIST_IS_SERVICES_VIKUNJA=true and
# the .existential.initialized sentinel is missing. Re-run manually with:
#   ./existential.sh run vikunja
#
# Runs on the host (uses `docker exec`). Requires: docker, vikunja container
# already started. If vikunja isn't running yet, the script prints what to do
# and exits cleanly — re-run setup after `docker compose up -d`.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

hr() { printf '%0.s─' {1..56}; echo; }
die() { echo "Error: $*" >&2; exit 1; }

# ── Source master .env so VIKUNJA_DEFAULT_* are available ─────────────────────

if [ -f "${REPO_DIR}/.env" ]; then
    set -a
    # shellcheck disable=SC1091
    . "${REPO_DIR}/.env"
    set +a
fi

USERNAME="${VIKUNJA_DEFAULT_USERNAME:-admin}"
PASSWORD="${VIKUNJA_DEFAULT_PASSWORD:-}"
EMAIL="${VIKUNJA_DEFAULT_EMAIL:-admin@localhost}"

echo ""
echo "  Vikunja initial setup"
hr
echo ""

[ -n "$PASSWORD" ] || die "VIKUNJA_DEFAULT_PASSWORD is not set. Edit services/vikunja/.env and re-run."

# ── Verify vikunja is up; skip gracefully if not ──────────────────────────────

if ! docker inspect vikunja --format '{{.State.Running}}' 2>/dev/null | grep -q true; then
    echo "  vikunja container is not running."
    echo ""
    echo "  Start it first, then re-run this step:"
    echo "    docker compose up -d vikunja vikunja-db"
    echo "    ./existential.sh run vikunja"
    echo ""
    exit 0
fi

# ── Create the user (idempotent — vikunja's `user create` errors if it exists) ─

echo "  Creating user '${USERNAME}' (${EMAIL})..."

if docker exec vikunja /app/vikunja/vikunja user list 2>/dev/null \
        | awk -v u="$USERNAME" '$0 ~ u { found=1 } END { exit !found }'; then
    echo "  User '${USERNAME}' already exists — nothing to do."
    echo ""
    exit 0
fi

if docker exec vikunja /app/vikunja/vikunja user create \
        --username "$USERNAME" \
        --password "$PASSWORD" \
        --email "$EMAIL"; then
    echo ""
    hr
    echo "  Done. Login at ${VIKUNJA_SERVICE_PUBLICURL:-https://vikunja.internal}"
    echo "    user:  ${USERNAME}"
    echo "    email: ${EMAIL}"
    echo ""
else
    die "vikunja user create failed. Inspect with: docker exec vikunja /app/vikunja/vikunja user list"
fi
