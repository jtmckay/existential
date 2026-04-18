#!/usr/bin/env bash
# Validates that saved Gmail credentials are still valid by refreshing the token
# and making a live API call. Non-destructive — read-only scope only.

set -euo pipefail

CREDENTIALS="${SECRETS_DIR:-/secrets}/gmail/credentials.env"

if [ ! -f "$CREDENTIALS" ]; then
    echo "No credentials at ${CREDENTIALS} — run: ./existential.sh setup gmail" >&2
    exit 1
fi

# shellcheck source=/dev/null
source "$CREDENTIALS"

[ -n "${GMAIL_CLIENT_ID:-}"     ] || { echo "Missing GMAIL_CLIENT_ID" >&2;     exit 1; }
[ -n "${GMAIL_CLIENT_SECRET:-}" ] || { echo "Missing GMAIL_CLIENT_SECRET" >&2; exit 1; }
[ -n "${GMAIL_REFRESH_TOKEN:-}" ] || { echo "Missing GMAIL_REFRESH_TOKEN" >&2; exit 1; }

_json_field() {
    local json="$1" key="$2"
    if command -v jq >/dev/null 2>&1; then
        printf '%s' "$json" | jq -r ".${key} // empty"
    else
        printf '%s' "$json" | python3 -c \
            "import sys,json; d=json.load(sys.stdin); print(d.get('${key}',''))"
    fi
}

TOKEN_RESPONSE=$(curl -sf --request POST \
    --data-urlencode "client_id=${GMAIL_CLIENT_ID}" \
    --data-urlencode "client_secret=${GMAIL_CLIENT_SECRET}" \
    --data-urlencode "refresh_token=${GMAIL_REFRESH_TOKEN}" \
    --data-urlencode "grant_type=refresh_token" \
    "https://oauth2.googleapis.com/token") || {
    echo "Token refresh failed — credentials may be revoked" >&2
    exit 1
}

ACCESS_TOKEN=$(_json_field "$TOKEN_RESPONSE" "access_token")

[ -n "$ACCESS_TOKEN" ] || {
    ERROR=$(_json_field "$TOKEN_RESPONSE" "error_description")
    echo "No access token: ${ERROR:-unknown error}" >&2
    exit 1
}

PROFILE=$(curl -sf \
    -H "Authorization: Bearer ${ACCESS_TOKEN}" \
    "https://gmail.googleapis.com/gmail/v1/users/me/profile") || {
    echo "Gmail API call failed" >&2
    exit 1
}

EMAIL=$(_json_field "$PROFILE" "emailAddress")
[ -n "$EMAIL" ] || { echo "Could not read email from profile response" >&2; exit 1; }

echo "Gmail: connected as ${EMAIL}"
