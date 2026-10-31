#!/usr/bin/env bash
# immich_setup — create Immich's admin and the read-only External Library.
#
# Runs as a decree migration (once). Without it, https://immich.<domain> opens
# on the admin sign-up page, then the onboarding wizard, and photos on the NAS
# (immich_share, mounted read-only at /mnt/media/external_photos) show up only
# after someone adds them as an External Library by hand. All of it is Immich's
# own API, verified against v3.3.5:
#   GET  /api/server/config                   isInitialized: an admin exists
#   POST /api/auth/admin-sign-up              (no auth) the first admin
#   POST /api/auth/login                      -> accessToken, userId
#   POST /api/system-metadata/admin-onboarding  skips the server wizard
#   PUT  /api/users/me/onboarding             skips the user wizard
#   POST /api/libraries, /api/libraries/:id/scan
#
# Idempotent the way homeassistant_onboarding is: an Immich that already has an
# admin (this migration or a person) is left alone, rather than guessing at a
# password for someone else's account.
#
# Env vars (passed through the decree container's compose env):
#   IMMICH_URL                                default http://immich-server:2283
#   IMMICH_ADMIN_EMAIL / IMMICH_ADMIN_NAME / IMMICH_ADMIN_PASSWORD
set -euo pipefail

IMMICH_URL="${IMMICH_URL:-http://immich-server:2283}"
LIBRARY_PATH=/mnt/media/external_photos

: "${IMMICH_ADMIN_EMAIL:?IMMICH_ADMIN_EMAIL not set}"
: "${IMMICH_ADMIN_PASSWORD:?IMMICH_ADMIN_PASSWORD not set}"

# _api METHOD PATH [JSON_BODY] — fails on a non-2xx status, printing Immich's
# own error body; curl's exit status alone would miss a 400.
_api() {
    local code body args
    body=$(mktemp)
    args=(-sS --max-time 30 -o "$body" -w '%{http_code}' -X "$1" "${IMMICH_URL}/api$2")
    [[ -n "${token:-}" ]] && args+=(-H "Authorization: Bearer ${token}")
    [[ -n "${3:-}" ]] && args+=(-H "Content-Type: application/json" -d "$3")
    code=$(curl "${args[@]}")
    if [[ "$code" != 2* ]]; then
        echo "$1 $2 -> ${code}: $(cat "$body")" >&2
        rm -f "$body"
        return 1
    fi
    cat "$body"
    rm -f "$body"
}

if [[ "$(_api GET /server/config | jq -r .isInitialized)" == true ]]; then
    echo "Immich already has an admin — nothing to do."
    exit 0
fi

echo "Creating the Immich admin (${IMMICH_ADMIN_EMAIL})..."
_api POST /auth/admin-sign-up "$(jq -n --arg email "$IMMICH_ADMIN_EMAIL" \
    --arg name "${IMMICH_ADMIN_NAME:-admin}" --arg password "$IMMICH_ADMIN_PASSWORD" \
    '{email: $email, name: $name, password: $password}')" >/dev/null

login=$(_api POST /auth/login "$(jq -n --arg email "$IMMICH_ADMIN_EMAIL" \
    --arg password "$IMMICH_ADMIN_PASSWORD" '{email: $email, password: $password}')")
token=$(jq -r .accessToken <<< "$login")
owner=$(jq -r .userId <<< "$login")

_api POST /system-metadata/admin-onboarding '{"isOnboarded": true}' >/dev/null
_api PUT /users/me/onboarding '{"isOnboarded": true}' >/dev/null

echo "Adding ${LIBRARY_PATH} as a read-only External Library..."
library=$(_api POST /libraries "$(jq -n --arg owner "$owner" --arg path "$LIBRARY_PATH" \
    '{ownerId: $owner, name: "NAS photos", importPaths: [$path]}')" | jq -r .id)
_api POST "/libraries/${library}/scan" >/dev/null

echo "Immich is set up — https://immich.<domain> opens on your photos."
