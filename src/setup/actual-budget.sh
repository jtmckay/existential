#!/usr/bin/env bash
# Actual Budget setup
#
# Connects to your Actual Budget server, lets you select a budget, and saves
# credentials to services/decree/secrets/actual-budget/credentials.env for use
# in decree routines.
#
# Run via: ./existential.sh setup actual-budget
# Requires: docker, running decree container with @actual-app/api available

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SECRETS_DIR="${SCRIPT_DIR}/../../services/decree/secrets"
CREDENTIALS="${SECRETS_DIR}/actual-budget/credentials.env"

hr() { printf '%0.s─' {1..56}; echo; }
die() { echo "Error: $*" >&2; exit 1; }

# ── Preflight ─────────────────────────────────────────────────────────────────

docker inspect decree --format '{{.State.Running}}' 2>/dev/null | grep -q true \
    || die "decree container is not running. Start it with: docker compose up -d"

echo ""
echo "  Actual Budget setup"
hr
echo ""

if [ -f "$CREDENTIALS" ]; then
    read -rp "  Credentials already exist. Replace? (y/N): " answer
    [[ "${answer,,}" == "y" ]] || { echo "Skipping."; exit 0; }
    echo ""
fi

# ── Collect server details ────────────────────────────────────────────────────

read -rp "  Server URL [http://actual-budget:5006]: " INPUT_URL
ACTUAL_URL="${INPUT_URL:-http://actual-budget:5006}"
echo ""

read -rsp "  Server password: " ACTUAL_PASSWORD
echo ""
echo ""

[ -n "$ACTUAL_PASSWORD" ] || die "Server password is required."

# ── Install @actual-app/api in decree container if needed ─────────────────────

echo "  Checking dependencies..."
if ! docker exec decree /work/.decree/lib/node_modules/.bin/tsx --version >/dev/null 2>&1; then
    echo "  Installing dependencies into /work/.decree/lib/..."
    docker exec decree sh -c "cd /work/.decree/lib && npm install 2>&1" \
        || die "Failed to install dependencies"
    echo "  Installed."
fi

# ── Run interactive setup via lib script ──────────────────────────────────────

echo ""
docker exec -it \
    -e ACTUAL_URL="$ACTUAL_URL" \
    -e ACTUAL_PASSWORD="$ACTUAL_PASSWORD" \
    -e SECRETS_DIR="/secrets/actual-budget" \
    decree /work/.decree/lib/node_modules/.bin/tsx /work/.decree/lib/actual-budget/setup.ts

# ── Enable routine in config.yml ─────────────────────────────────────────────

CONFIG="${SCRIPT_DIR}/../../automations/config.yml"
if [ -f "$CONFIG" ]; then
    awk '
        /^  actual-budget:$/ { found=1 }
        found && /enabled:/ { sub(/enabled: .*/, "enabled: true"); found=0 }
        { print }
    ' "$CONFIG" > "${CONFIG}.tmp" && mv "${CONFIG}.tmp" "$CONFIG"
    echo "  Routine 'actual-budget' enabled in automations/config.yml."
fi

echo ""
hr
echo ""
echo "  Done. Restart decree to apply:"
echo ""
echo "    docker compose -f services/decree/docker-compose.yml restart decree"
echo ""
