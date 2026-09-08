#!/usr/bin/env bash
# homeassistant-onboarding — complete HA's setup wizard headlessly.
#
# Runs as a decree migration (once). A fresh Home Assistant install redirects
# every page to /onboarding.html until FOUR steps are marked done: user,
# core_config, analytics, integration (homeassistant/components/onboarding/
# views.py, verified against 2026.8.2 source) — without this, the browser
# lands on the setup wizard instead of the dashboard on first login.
#
# All four are HA's own public onboarding API, exactly what onboarding.html's
# own JS calls:
#   POST /api/onboarding/users        (no auth) -> {"auth_code": ...}
#   POST /auth/token                  exchange auth_code for an access_token
#   POST /api/onboarding/core_config  (Bearer)
#   POST /api/onboarding/analytics    (Bearer)
#   POST /api/onboarding/integration  (Bearer) {client_id, redirect_uri}
#
# client_id/redirect_uri just need matching scheme+host (indieauth.py's
# verify_redirect_uri) — a bare container hostname like "homeassistant" needs
# no DNS-resolvable client_id page, since indieauth.py's own IP check only
# applies when the netloc parses as an IP address.
#
# Idempotent: only the "user" step is checked up front. If it's already done
# (a previous run, or someone completed the wizard by hand) this exits
# immediately rather than guessing at a password to log in with — the
# remaining steps are cosmetic (default integrations, analytics opt-in) and
# not worth the risk of a wrong assumption on a real account.
#
# Env vars (passed through the decree container's compose env):
#   HOMEASSISTANT_URL                              default http://homeassistant:8123
#   HOMEASSISTANT_ADMIN_USER / HOMEASSISTANT_ADMIN_PASSWORD
set -euo pipefail

HOMEASSISTANT_URL="${HOMEASSISTANT_URL:-http://homeassistant:8123}"
CLIENT_ID="${HOMEASSISTANT_URL%/}/"

if [[ "${DECREE_PRE_CHECK:-}" == "true" ]]; then
    command -v curl >/dev/null 2>&1                || { echo "curl not found" >&2; exit 1; }
    command -v jq >/dev/null 2>&1                   || { echo "jq not found" >&2; exit 1; }
    [[ -n "${HOMEASSISTANT_ADMIN_USER:-}" ]]        || { echo "HOMEASSISTANT_ADMIN_USER not set" >&2; exit 1; }
    [[ -n "${HOMEASSISTANT_ADMIN_PASSWORD:-}" ]]    || { echo "HOMEASSISTANT_ADMIN_PASSWORD not set" >&2; exit 1; }
    exit 0
fi

# _post PATH [BEARER] [JSON_BODY] — checks the HTTP status itself: every
# onboarding view answers 200 with a JSON body on success and a JSON error
# message on failure (HTTPStatus.FORBIDDEN/BAD_REQUEST), so curl's own exit
# status alone would miss a logical failure.
_post() {
    local path="$1" bearer="${2:-}" data="${3:-}" code body args=()
    body=$(mktemp)
    args=(-sS --max-time 10 -o "$body" -w '%{http_code}' -X POST "${HOMEASSISTANT_URL}${path}")
    [[ -n "$bearer" ]] && args+=(-H "Authorization: Bearer ${bearer}")
    if [[ -n "$data" ]]; then
        args+=(-H "Content-Type: application/json" -d "$data")
    fi
    code=$(curl "${args[@]}")
    if [[ "$code" != 2* ]]; then
        echo "POST ${path} -> ${code}: $(cat "$body")" >&2
        rm -f "$body"
        return 1
    fi
    cat "$body"
    rm -f "$body"
}

steps=$(curl -sS --max-time 10 "${HOMEASSISTANT_URL}/api/onboarding")
if [[ "$(echo "$steps" | jq -r '.[] | select(.step=="user") | .done')" == "true" ]]; then
    echo "Home Assistant onboarding already has a user — nothing to do."
    exit 0
fi

echo "Creating the Home Assistant admin account (${HOMEASSISTANT_ADMIN_USER})..."
auth_code=$(_post "/api/onboarding/users" "" "$(jq -n \
    --arg name "$HOMEASSISTANT_ADMIN_USER" \
    --arg user "$HOMEASSISTANT_ADMIN_USER" \
    --arg pass "$HOMEASSISTANT_ADMIN_PASSWORD" \
    --arg client_id "$CLIENT_ID" \
    '{name: $name, username: $user, password: $pass, client_id: $client_id, language: "en"}')" \
    | jq -r '.auth_code')
[[ -n "$auth_code" && "$auth_code" != "null" ]] || { echo "No auth_code in users response" >&2; exit 1; }

token_response=$(curl -sS --max-time 10 -X POST "${HOMEASSISTANT_URL}/auth/token" \
    --data-urlencode "client_id=${CLIENT_ID}" \
    --data-urlencode "grant_type=authorization_code" \
    --data-urlencode "code=${auth_code}")
access_token=$(echo "$token_response" | jq -r '.access_token // empty')
[[ -n "$access_token" ]] || { echo "Token exchange failed: ${token_response}" >&2; exit 1; }

echo "Finishing core_config, analytics and integration steps..."
_post "/api/onboarding/core_config" "$access_token" >/dev/null
_post "/api/onboarding/analytics" "$access_token" >/dev/null
_post "/api/onboarding/integration" "$access_token" "$(jq -n \
    --arg client_id "$CLIENT_ID" \
    --arg redirect_uri "${CLIENT_ID}?auth_callback=1" \
    '{client_id: $client_id, redirect_uri: $redirect_uri}')" >/dev/null

echo "Home Assistant onboarding complete — https://homeassistant.<domain> now serves the real UI."
