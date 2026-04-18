#!/usr/bin/env bash
# ntfy setup
#
# Walks through obtaining an ntfy access token and URL after the stack is
# running, then updates the root .env and services/decree/.env in place.
#
# Run via: ./existential.sh setup ntfy
# Or directly in the adhoc container: bash /src/setup/ntfy.sh

set -euo pipefail

# ── Paths ─────────────────────────────────────────────────────────────────────

REPO_DIR="${REPO_DIR:-/repo}"
ROOT_ENV="${REPO_DIR}/.env"
DECREE_ENV="${REPO_DIR}/services/decree/.env"

# ── Helpers ───────────────────────────────────────────────────────────────────

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

test_ntfy() {
    local url="$1" token="$2"
    local health
    health=$(curl -sf --max-time 5 "${url}/v1/health" 2>/dev/null) || return 1
    echo "$health" | grep -q '"healthy":true' || return 1

    if [ -n "$token" ]; then
        curl -sf --max-time 5 \
            -H "Authorization: Bearer ${token}" \
            "${url}/v1/account" >/dev/null 2>&1 || return 1
    fi
}

# ── Read current values ────────────────────────────────────────────────────────

CURRENT_URL=""
CURRENT_TOKEN=""
if [ -f "$ROOT_ENV" ]; then
    CURRENT_URL=$(env_get "$ROOT_ENV" "EXIST_DEFAULT_NTFY_URL")
    CURRENT_TOKEN=$(env_get "$ROOT_ENV" "EXIST_DEFAULT_NTFY_TOKEN")
fi

# ── Intro ─────────────────────────────────────────────────────────────────────

echo ""
echo "  ntfy integration setup"
hr
echo ""
echo "  This connects Decree (and other services) to your ntfy instance."
echo "  You need ntfy running before completing this step."
echo ""

if [ -n "$CURRENT_URL" ]; then
    echo "  Current URL:   ${CURRENT_URL}"
fi
if [ -n "$CURRENT_TOKEN" ]; then
    echo "  Current token: ${CURRENT_TOKEN}"
fi
echo ""

# ── URL ───────────────────────────────────────────────────────────────────────

DEFAULT_URL="${CURRENT_URL:-http://ntfy:80}"
read -rp "  ntfy URL [${DEFAULT_URL}]: " INPUT_URL
NTFY_URL="${INPUT_URL:-$DEFAULT_URL}"

echo ""
echo "  Testing connectivity to ${NTFY_URL}..."
if curl -sf --max-time 5 "${NTFY_URL}/v1/health" 2>/dev/null | grep -q '"healthy":true'; then
    echo "  ntfy is reachable."
else
    echo ""
    echo "  Warning: could not reach ${NTFY_URL}/v1/health"
    echo "  Continuing anyway — make sure ntfy is running before using integrations."
fi

# ── Token ─────────────────────────────────────────────────────────────────────

echo ""
hr
echo ""
echo "  You need an ntfy access token for the bot user."
echo ""
echo "  Option A — use the auto-generated token from initial setup:"
if [ -n "$CURRENT_TOKEN" ]; then
    echo "    ${CURRENT_TOKEN}"
else
    echo "    (not found in ${ROOT_ENV})"
fi
echo ""
echo "  Option B — create a new token in the ntfy UI:"
echo "    1. Open ${NTFY_URL} in your browser"
echo "    2. Sign in as the bot user"
echo "    3. Account → Access tokens → Create access token"
echo "    4. Copy the token and paste it below"
echo ""

read -rp "  Access token [keep current]: " INPUT_TOKEN
NTFY_TOKEN="${INPUT_TOKEN:-$CURRENT_TOKEN}"

[ -n "$NTFY_TOKEN" ] || die "No token provided and no existing token found."

# ── Verify token ──────────────────────────────────────────────────────────────

echo ""
echo "  Verifying token..."
if curl -sf --max-time 5 \
    -H "Authorization: Bearer ${NTFY_TOKEN}" \
    "${NTFY_URL}/v1/account" >/dev/null 2>&1; then
    echo "  Token accepted."
else
    echo ""
    echo "  Warning: token verification failed (ntfy may not be reachable, or token is invalid)."
    read -rp "  Save anyway? (y/N): " confirm
    [[ "${confirm,,}" == "y" ]] || { echo "Aborted."; exit 0; }
fi

# ── Write values ──────────────────────────────────────────────────────────────

echo ""

if [ -f "$ROOT_ENV" ]; then
    env_set "$ROOT_ENV" "EXIST_DEFAULT_NTFY_URL"   "$NTFY_URL"
    env_set "$ROOT_ENV" "EXIST_DEFAULT_NTFY_TOKEN" "$NTFY_TOKEN"
    echo "  Updated ${ROOT_ENV}"
else
    echo "  Warning: ${ROOT_ENV} not found — skipping root .env update."
fi

if [ -f "$DECREE_ENV" ]; then
    env_set "$DECREE_ENV" "NTFY_URL"   "$NTFY_URL"
    env_set "$DECREE_ENV" "NTFY_TOKEN" "$NTFY_TOKEN"
    echo "  Updated ${DECREE_ENV}"
else
    echo "  Warning: ${DECREE_ENV} not found — skipping decree .env update."
fi

_CONFIG="${DECREE_DIR:-/work/.decree}/config.yml"
if [ -f "$_CONFIG" ]; then
    awk '
        /^  notify:$/ { found=1 }
        found && /enabled:/ { sub(/enabled: .*/, "enabled: true"); found=0 }
        { print }
    ' "$_CONFIG" > "${_CONFIG}.tmp" && mv "${_CONFIG}.tmp" "$_CONFIG"
    echo "  Routine 'notify' enabled in config.yml."
fi

echo ""
hr
echo ""
echo "  Restart decree to apply:"
echo ""
echo "    docker compose -f services/decree/docker-compose.yml restart decree"
echo ""
