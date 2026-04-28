#!/usr/bin/env bash
# gmail-sync setup
#
# One-time OAuth 2.0 authorization for the gmail-sync routine.
# Requests the gmail.readonly scope — read-only access only.
# Credentials are written to ${SECRETS_DIR}/gmail/credentials.env (gitignored).
#
# Run via: ./existential.sh setup gmail
# Or directly in the adhoc container: bash /src/setup/gmail-sync.sh
#
# Requires: curl, bash 4+
# python3 is used for URL-decoding (optional; falls back to raw code).

set -euo pipefail

# ── Paths ─────────────────────────────────────────────────────────────────────

if [ -z "${SECRETS_DIR:-}" ]; then
    if [ "${IN_CONTAINER:-}" = "1" ]; then
        SECRETS_DIR="/secrets"
    else
        # Host fallback: run via ./existential.sh setup gmail instead
        SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        SECRETS_DIR="${SCRIPT_DIR}/../../services/decree/secrets"
    fi
fi

GMAIL_DIR="${GMAIL_DIR:-${SECRETS_DIR}/gmail}"
CREDENTIALS="${GMAIL_DIR}/credentials.env"

# ── OAuth config ──────────────────────────────────────────────────────────────

REDIRECT_URI="http://localhost:8803"
SCOPE_ENC="https%3A%2F%2Fwww.googleapis.com%2Fauth%2Fgmail.readonly"
REDIRECT_ENC="http%3A%2F%2Flocalhost%3A8803"

# ── Helpers ───────────────────────────────────────────────────────────────────

hr() { printf '%0.s═' {1..56}; echo; }
die() { echo "Error: $*" >&2; exit 1; }

# Parse a JSON field without requiring jq on the host
json_field() {
    local json="$1" key="$2"
    if command -v jq >/dev/null 2>&1; then
        printf '%s' "$json" | jq -r ".${key} // empty"
    else
        printf '%s' "$json" | python3 -c \
            "import sys,json; d=json.load(sys.stdin); print(d.get('${key}',''))"
    fi
}

# ── Main ──────────────────────────────────────────────────────────────────────

_REAUTH=false
if [ -f "$CREDENTIALS" ]; then
    echo "Credentials already exist at ${CREDENTIALS}."
    echo ""
    echo "  [r] Reauthorize — keep existing client ID & secret, get a new refresh token"
    echo "  [d] Delete old credentials — enter a new client ID and secret too"
    echo "  [s] Skip (default)"
    echo ""
    read -rp "Choice [r/d/s]: " answer
    case "${answer}" in
        r) _REAUTH=true ;;
        d) ;;  # fall through to full entry below
        *) echo "Skipping."; exit 0 ;;
    esac
    echo ""
fi

if [ "$_REAUTH" = "true" ]; then
    # Load existing credentials — just the client pair, not the refresh token
    # shellcheck disable=SC1090
    source "$CREDENTIALS"
    CLIENT_ID="${GMAIL_CLIENT_ID:?GMAIL_CLIENT_ID missing from ${CREDENTIALS}}"
    CLIENT_SECRET="${GMAIL_CLIENT_SECRET:?GMAIL_CLIENT_SECRET missing from ${CREDENTIALS}}"
    echo "Using existing Client ID: ${CLIENT_ID}"
    echo ""
else
    echo "You need a Google Cloud OAuth 2.0 Client ID (Desktop app type)."
    echo ""
    echo "  1. https://console.cloud.google.com/apis/credentials"
    echo "  2. Create/select a project → enable the Gmail API"
    echo "  3. Create Credentials → OAuth 2.0 Client ID → Desktop app"
    echo "  4. Add redirect URI:  ${REDIRECT_URI}"
    echo "  5. Note your Client ID and Client Secret"
    echo ""

    read -rp  "Client ID:     " CLIENT_ID
    read -rsp "Client Secret: " CLIENT_SECRET
    echo ""

    [ -n "$CLIENT_ID" ]     || die "Client ID is required"
    [ -n "$CLIENT_SECRET" ] || die "Client Secret is required"
fi

AUTH_URL="https://accounts.google.com/o/oauth2/v2/auth\
?client_id=${CLIENT_ID}\
&redirect_uri=${REDIRECT_ENC}\
&response_type=code\
&scope=${SCOPE_ENC}\
&access_type=offline\
&prompt=consent"

echo ""
hr
echo "  Open this URL in your browser:"
hr
echo ""
echo "${AUTH_URL}"
echo ""
echo "Waiting for authorization (timeout: 2 minutes)..."
echo ""

_CODE_FILE="$(mktemp)"

python3 - "$_CODE_FILE" << 'PYEOF' &
import http.server, urllib.parse, sys

code_file = sys.argv[1]

class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        params = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
        code = urllib.parse.unquote(params.get('code', [''])[0])
        self.send_response(200)
        self.send_header('Content-type', 'text/html')
        self.end_headers()
        self.wfile.write(
            b'<html><body style="font-family:sans-serif;padding:2rem">'
            b'<h2>Authorization complete!</h2>'
            b'<p>You may close this tab and return to the terminal.</p>'
            b'</body></html>'
        )
        with open(code_file, 'w') as f:
            f.write(code)
    def log_message(self, *args):
        pass

with http.server.HTTPServer(('0.0.0.0', 8803), Handler) as httpd:
    httpd.handle_request()
PYEOF

_SERVER_PID=$!
( sleep 120; kill "$_SERVER_PID" 2>/dev/null ) &
_KILLER_PID=$!

wait "$_SERVER_PID" 2>/dev/null || true
kill "$_KILLER_PID" 2>/dev/null || true

if [[ -s "$_CODE_FILE" ]]; then
    CODE=$(cat "$_CODE_FILE")
    rm -f "$_CODE_FILE"
else
    rm -f "$_CODE_FILE"
    echo "Automatic capture timed out. Paste the redirect URL manually."
    echo ""
    read -rp "Redirect URL: " REDIRECT_URL
    CODE_REGEX='[?&]code=([^&]+)'
    [[ "$REDIRECT_URL" =~ $CODE_REGEX ]] || die "Could not find 'code=' in the URL you pasted"
    CODE=$(python3 -c "import urllib.parse,sys; print(urllib.parse.unquote(sys.argv[1]))" "${BASH_REMATCH[1]}")
fi

echo ""
echo "Exchanging authorization code for tokens..."

TOKEN_RESPONSE=$(curl -sf --request POST \
    --data-urlencode "code=${CODE}" \
    --data-urlencode "client_id=${CLIENT_ID}" \
    --data-urlencode "client_secret=${CLIENT_SECRET}" \
    --data-urlencode "redirect_uri=${REDIRECT_URI}" \
    --data-urlencode "grant_type=authorization_code" \
    "https://oauth2.googleapis.com/token") || die "Token exchange failed"

REFRESH_TOKEN=$(json_field "$TOKEN_RESPONSE" "refresh_token")
ACCESS_TOKEN=$(json_field  "$TOKEN_RESPONSE" "access_token")

if [ -z "$REFRESH_TOKEN" ]; then
    ERROR=$(json_field "$TOKEN_RESPONSE" "error_description")
    echo ""
    echo "No refresh token returned: ${ERROR:-$(json_field "$TOKEN_RESPONSE" "error")}"
    echo ""
    echo "The app was likely already authorized without 'prompt=consent'."
    echo "Revoke access at https://myaccount.google.com/permissions then re-run."
    exit 1
fi

PROFILE=$(curl -sf \
    -H "Authorization: Bearer ${ACCESS_TOKEN}" \
    "https://gmail.googleapis.com/gmail/v1/users/me/profile") \
    || die "Could not verify Gmail access — check your credentials"

EMAIL=$(json_field "$PROFILE" "emailAddress")
HISTORY_ID=$(json_field "$PROFILE" "historyId")

echo "Connected as: ${EMAIL}"

mkdir -p "$GMAIL_DIR"
chmod 700 "$GMAIL_DIR"

cat > "${CREDENTIALS}.tmp" << EOF
GMAIL_CLIENT_ID=${CLIENT_ID}
GMAIL_CLIENT_SECRET=${CLIENT_SECRET}
GMAIL_REFRESH_TOKEN=${REFRESH_TOKEN}
EOF
chmod 600 "${CREDENTIALS}.tmp"
mv "${CREDENTIALS}.tmp" "$CREDENTIALS"

echo "Credentials saved to ${CREDENTIALS}"
echo ""
echo "  The routine will backfill the last 30 days on first run."
echo "  To skip the backfill and start from now instead, create the state file:"
echo ""
echo "    echo '${HISTORY_ID}' > ${GMAIL_DIR}/history_id"
echo ""

# Enable the gmail-sync routine in config.yml
_CONFIG="${DECREE_DIR:-/work/.decree}/config.yml"
if [ -f "$_CONFIG" ]; then
    awk '
        /^  gmail-sync:$/ { found=1 }
        found && /enabled:/ { sub(/enabled: .*/, "enabled: true"); found=0 }
        { print }
    ' "$_CONFIG" > "${_CONFIG}.tmp" && mv "${_CONFIG}.tmp" "$_CONFIG"
    echo "Routine 'gmail-sync' enabled in config.yml."
    echo "Restart the daemon to apply: docker compose restart decree"
fi

# ── Sync label cache ──────────────────────────────────────────────────────────

echo ""
bash /src/setup/gmail-labels.sh
