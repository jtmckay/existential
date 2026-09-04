#!/usr/bin/env bash
# Actual Budget — connect Decree to your Actual Budget server
#
# Sets the server's login password if it doesn't have one yet (actual-server
# has no env var for this — see the comment above `environment:` in
# docker-compose.exist.yml), then connects with @actual-app/api, lets you
# select a budget, and saves credentials to
# automation/secrets/actual-budget/credentials.env for use in decree
# routines.
#
# This is a manual step, not auto-run by `./existential.sh` — there is no
# sentinel for it. Run it once `docker compose up -d` has actual-budget and
# decree running, and re-run any time (e.g. after adding accounts) with:
#   ./existential.sh run actual-budget setup
#
# Runs on the host (uses `docker exec automation`). Requires: docker.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SECRETS_DIR="${REPO_DIR}/automation/secrets"
CREDENTIALS="${SECRETS_DIR}/actual-budget/credentials.env"

hr() { printf '%0.s─' {1..56}; echo; }
die() { echo "Error: $*" >&2; exit 1; }

# ── Preflight ─────────────────────────────────────────────────────────────────

if ! docker inspect automation --format '{{.State.Running}}' 2>/dev/null | grep -q true; then
    echo "  actual-budget credential setup requires decree to be running."
    echo "  Start containers, then complete setup with:"
    echo ""
    echo "    docker compose up -d"
    echo "    ./existential.sh run actual-budget setup"
    echo ""
    exit 0
fi

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

# ── Bootstrap the server password if it doesn't have one yet ──────────────────
# actual-server sets its login password exactly once, via POST /account/bootstrap
# — normally triggered by the web UI's first visit. Do that here too, so this
# script alone is enough for a server nobody has opened in a browser yet.
# /account/needs-bootstrap runs a real `SELECT * FROM auth` against the account
# DB (not a canned response), and bootstrapping an already-bootstrapped server
# is a safe no-op (400 "already-bootstrapped") — confirmed against a live
# actualbudget/actual-server:26.8.1 container.

NEEDS_BOOTSTRAP=$(docker exec automation curl -sS --max-time 5 "${ACTUAL_URL}/account/needs-bootstrap" 2>/dev/null \
    | grep -o '"bootstrapped":[a-z]*' | cut -d: -f2)

case "$NEEDS_BOOTSTRAP" in
    false)
        echo "  Server already has a password set."
        ;;
    true)
        echo "  Setting the server password..."
        docker exec -e ACTUAL_URL="$ACTUAL_URL" -e ACTUAL_PASSWORD="$ACTUAL_PASSWORD" automation sh -c '
            payload=$(jq -n --arg pw "$ACTUAL_PASSWORD" "{password: \$pw}")
            curl -sS -f -X POST "$ACTUAL_URL/account/bootstrap" \
                -H "Content-Type: application/json" -d "$payload" >/dev/null
        ' || die "Failed to set the server password. Is ${ACTUAL_URL} reachable from decree?"
        echo "  Password set."
        ;;
    *)
        die "Could not reach ${ACTUAL_URL}/account/needs-bootstrap — is the actual-budget container running?"
        ;;
esac
echo ""

# ── Install @actual-app/api in decree container if needed ─────────────────────

echo "  Checking dependencies..."
if ! docker exec automation /work/.decree/lib/node_modules/.bin/tsx --version >/dev/null 2>&1; then
    echo "  Installing dependencies into /work/.decree/lib/..."
    docker exec automation sh -c "cd /work/.decree/lib && npm install 2>&1" \
        || die "Failed to install dependencies"
    echo "  Installed."
fi

# ── Run interactive setup via lib script ──────────────────────────────────────

echo ""
docker exec -it \
    -e ACTUAL_URL="$ACTUAL_URL" \
    -e ACTUAL_PASSWORD="$ACTUAL_PASSWORD" \
    -e SECRETS_DIR="/secrets/actual-budget" \
    automation /work/.decree/lib/node_modules/.bin/tsx /work/.decree/lib/actual-budget/setup.ts

# ── Enable routine in config.yml ─────────────────────────────────────────────
# The rendered config lives with the decree image build, not at the repo-root
# automation/ (which is wholesale-mounted read-write into the container, but
# config.yml is deliberately layered in from here instead — see
# .claude/skills/decree/SKILL.md for why).

CONFIG="${REPO_DIR}/services/automation/decree/config.yml"
if [ -f "$CONFIG" ]; then
    awk '
        /^  actual-budget:$/ { found=1 }
        found && /enabled:/ { sub(/enabled: .*/, "enabled: true"); found=0 }
        { print }
    ' "$CONFIG" > "${CONFIG}.tmp" && mv "${CONFIG}.tmp" "$CONFIG"
    echo "  Routine 'actual-budget' enabled in services/automation/decree/config.yml."
fi

echo ""
hr
echo ""
echo "  Done. Restart decree to apply:"
echo ""
echo "    docker compose restart automation   # from the repo root"
echo ""
