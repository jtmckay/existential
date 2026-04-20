#!/usr/bin/env bash
# Gmail label sync
#
# Fetches all Gmail labels and saves them to ${GMAIL_DIR}/labels.json.
# Used by the gmail-sync routine to resolve custom label names to IDs
# without making an API call on every run.
#
# Run via: ./existential.sh setup gmail-labels
# Or directly in the adhoc container: bash /src/setup/gmail-labels.sh
#
# Requires Gmail credentials to already exist (run ./existential.sh setup gmail first).

set -euo pipefail

GMAIL_DIR="${GMAIL_DIR:-/secrets/gmail}"
CREDENTIALS="${GMAIL_DIR}/credentials.env"
LABELS_FILE="${GMAIL_DIR}/labels.json"

hr() { printf '%0.s─' {1..56}; echo; }
die() { echo "Error: $*" >&2; exit 1; }

json_field() {
    local json="$1" key="$2"
    if command -v jq >/dev/null 2>&1; then
        printf '%s' "$json" | jq -r ".${key} // empty"
    else
        python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('${key}',''))" <<< "$json"
    fi
}

echo ""
echo "  Gmail label sync"
hr
echo ""

[ -f "$CREDENTIALS" ] || die "Gmail credentials not found at ${CREDENTIALS}. Run: ./existential.sh setup gmail"

# shellcheck source=/dev/null
source "$CREDENTIALS"

: "${GMAIL_CLIENT_ID:?GMAIL_CLIENT_ID not set in credentials.env}"
: "${GMAIL_CLIENT_SECRET:?GMAIL_CLIENT_SECRET not set in credentials.env}"
: "${GMAIL_REFRESH_TOKEN:?GMAIL_REFRESH_TOKEN not set in credentials.env}"

# ── Get access token ──────────────────────────────────────────────────────────

echo "  Refreshing access token..."
TOKEN_RESPONSE=$(curl -sf --request POST \
    --data-urlencode "client_id=${GMAIL_CLIENT_ID}" \
    --data-urlencode "client_secret=${GMAIL_CLIENT_SECRET}" \
    --data-urlencode "refresh_token=${GMAIL_REFRESH_TOKEN}" \
    --data-urlencode "grant_type=refresh_token" \
    "https://oauth2.googleapis.com/token")

ACCESS_TOKEN=$(json_field "$TOKEN_RESPONSE" "access_token")
[ -n "$ACCESS_TOKEN" ] || die "Token refresh failed: $(json_field "$TOKEN_RESPONSE" "error_description")"

# ── Fetch labels ──────────────────────────────────────────────────────────────

echo "  Fetching labels..."
LABELS=$(curl -sf \
    -H "Authorization: Bearer ${ACCESS_TOKEN}" \
    "https://gmail.googleapis.com/gmail/v1/users/me/labels") \
    || die "Failed to fetch labels"

# ── Save ──────────────────────────────────────────────────────────────────────

printf '%s\n' "$LABELS" > "${LABELS_FILE}.tmp"
mv "${LABELS_FILE}.tmp" "$LABELS_FILE"

COUNT=$(printf '%s' "$LABELS" | jq '.labels | length')
echo "  Saved ${COUNT} labels to ${LABELS_FILE}"
echo ""

printf '%s' "$LABELS" | jq -r '.labels[] | "  \(.type | ascii_downcase | .[0:6]) \(.name)"' | sort
echo ""
hr
echo ""
echo "  Label cache is current. The gmail-sync routine will use this"
echo "  file to resolve custom label names. Re-run this command if you"
echo "  add new labels in Gmail:"
echo ""
echo "    ./existential.sh setup gmail-labels"
echo ""
