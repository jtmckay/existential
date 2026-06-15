#!/usr/bin/env bash
# ntfy — first-time user and token setup
#
# Creates the admin and bot users in ntfy's auth DB, generates a bot access
# token, and saves EXIST_NTFY_URL + EXIST_NTFY_TOKEN to the root .env for use
# by decree and other services.
#
# Requires ntfy to be running. Run after 'docker compose up -d':
#   ./existential.sh run ntfy setup

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
# .env.shared is the compose-generation source — write there so the next
# existential.sh run regenerates docker-compose.yml with the real token.
ROOT_ENV="${REPO_DIR}/.env.shared"

hr()      { printf '%0.s─' {1..56}; echo; }
die()     { echo "Error: $*" >&2; exit 1; }
section() { echo ""; echo "  $*"; }

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

ntfy_exec() { docker exec ntfy ntfy "$@"; }

# ── Pre-flight: ntfy must be running ─────────────────────────────────────────

if ! docker ps --format '{{.Names}}' | grep -q '^ntfy$'; then
    die "ntfy container is not running. Start it with: docker compose up -d ntfy"
fi

echo ""
echo "  ntfy setup"
hr

# ── Admin user ───────────────────────────────────────────────────────────────

section "Admin user"
if ntfy_exec user list 2>/dev/null | grep -q '^admin'; then
    echo "  already exists — skipping"
else
    read -rsp "  Password for admin: " ADMIN_PASS; echo
    docker exec -e NTFY_PASSWORD="$ADMIN_PASS" ntfy ntfy user add --role=admin admin
    echo "  admin created."
fi

# ── Bot user ─────────────────────────────────────────────────────────────────

section "Bot user"
if ntfy_exec user list 2>/dev/null | grep -q '^bot'; then
    echo "  already exists — skipping"
else
    read -rsp "  Password for bot: " BOT_PASS; echo
    docker exec -e NTFY_PASSWORD="$BOT_PASS" ntfy ntfy user add bot
    echo "  bot created."
fi
ntfy_exec access bot "exist*" rw
echo "  bot access rule (exist*:rw) applied."

# ── Bot access token ─────────────────────────────────────────────────────────

section "Bot token"
CURRENT_TOKEN=""
[ -f "$ROOT_ENV" ] && CURRENT_TOKEN=$(env_get "$ROOT_ENV" "EXIST_NTFY_TOKEN")

NTFY_TOKEN=""
if [ -n "$CURRENT_TOKEN" ]; then
    echo "  EXIST_NTFY_TOKEN already set: ${CURRENT_TOKEN}"
    read -rp "  Generate a new token? (y/N): " regen
    [[ "${regen,,}" == "y" ]] || NTFY_TOKEN="$CURRENT_TOKEN"
fi

if [ -z "$NTFY_TOKEN" ]; then
    TOKEN_OUTPUT=$(ntfy_exec token add bot 2>&1)
    NTFY_TOKEN=$(echo "$TOKEN_OUTPUT" | grep -oE 'tk_[a-z0-9]+' | head -1)
    [ -n "$NTFY_TOKEN" ] || die "Could not parse token from output: ${TOKEN_OUTPUT}"
    echo "  Token generated: ${NTFY_TOKEN}"
fi

# ── Save to root .env ────────────────────────────────────────────────────────

if [ -f "$ROOT_ENV" ]; then
    env_set "$ROOT_ENV" "EXIST_NTFY_URL"   "http://ntfy:80"
    env_set "$ROOT_ENV" "EXIST_NTFY_TOKEN" "$NTFY_TOKEN"
    echo ""
    echo "  Saved EXIST_NTFY_URL and EXIST_NTFY_TOKEN to ${ROOT_ENV}"
fi

echo ""
hr
echo ""
echo "  Re-render and restart decree to apply:"
echo ""
echo "    ./existential.sh && docker compose up -d decree"
echo ""
