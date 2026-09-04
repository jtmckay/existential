#!/usr/bin/env bash
# ntfy — optional token setup.
#
# NOT required. ntfy's own entrypoint (services/ntfy/entrypoint.sh) creates the
# admin and bot users from EXIST_NTFY_USER / EXIST_NTFY_PASSWORD on first boot,
# and notify.sh publishes with those over basic auth — so a fresh install works
# with no input at all.
#
# Run this only when you want a bearer TOKEN instead: it mints one for the bot
# and writes EXIST_NTFY_TOKEN to .env.shared, which takes precedence over the
# user/password everywhere it is read. It also still creates the users, for an
# install that predates the entrypoint.
#
# Requires ntfy to be running. Prompts for passwords only for users that do not
# already exist:
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

ADMIN_USER=$(env_get "${SCRIPT_DIR}/.env" NTFY_ADMIN_USER); ADMIN_USER="${ADMIN_USER:-admin}"
BOT_USER=$(env_get "$ROOT_ENV" EXIST_NTFY_USER);              BOT_USER="${BOT_USER:-bot}"

section "Admin user"
# `ntfy user list` prints "user <name> (role: ...)" — the name is the SECOND
# field. Anchoring on the first (as this used to) never matches, so every run
# fell through to `ntfy user add` on a user that already existed, which exits
# 1 under `set -euo pipefail` and aborted the script before it minted a token.
# Verified against a real v2.27.0 container. Same fix as entrypoint.sh's
# `_have_user`, which got this right.
if ntfy_exec user list 2>/dev/null | grep -q "^user ${ADMIN_USER} "; then
    echo "  already exists — skipping"
else
    read -rsp "  Password for ${ADMIN_USER}: " ADMIN_PASS; echo
    docker exec -e NTFY_PASSWORD="$ADMIN_PASS" ntfy ntfy user add --role=admin "$ADMIN_USER"
    echo "  ${ADMIN_USER} created."
fi

# ── Bot user ─────────────────────────────────────────────────────────────────

section "Bot user"
if ntfy_exec user list 2>/dev/null | grep -q "^user ${BOT_USER} "; then
    echo "  already exists — skipping"
else
    read -rsp "  Password for ${BOT_USER}: " BOT_PASS; echo
    docker exec -e NTFY_PASSWORD="$BOT_PASS" ntfy ntfy user add "$BOT_USER"
    echo "  ${BOT_USER} created."
fi
BOT_TOPICS=$(env_get "$ROOT_ENV" EXIST_NTFY_TOPICS); BOT_TOPICS="${BOT_TOPICS:-*}"
ntfy_exec access "$BOT_USER" "$BOT_TOPICS" rw
echo "  ${BOT_USER} access rule (${BOT_TOPICS}:rw) applied."

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
    TOKEN_OUTPUT=$(ntfy_exec token add "$BOT_USER" 2>&1)
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
echo "  Re-render and restart automation to apply:"
echo ""
echo "    ./existential.sh && docker compose up -d decree"
echo ""
