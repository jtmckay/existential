#!/usr/bin/env bash
# caddy — first-time / optional public-domain setup.
#
# By default the homelab is local-only: Caddy fronts each service at
# `<slug>.<EXIST_DOMAIN>` with the pinned internal leaf. Devices that imported
# the root cert get a green padlock; others see a warning.
#
# This script walks the user through opting in to a PUBLIC domain so each
# service is also reachable at `<slug>.<EXIST_PUBLIC_DOMAIN>` with real
# (Let's Encrypt) HTTPS certs. The public-domain blocks are ADDITIVE —
# existing `<slug>.<EXIST_DOMAIN>` blocks remain untouched.
#
# Mechanism: this script parses the live Caddyfile for every
# `<slug>.<EXIST_DOMAIN> { ... }` block, emits a parallel `<slug>.<domain> { ... }`
# block (with `tls internal` stripped so Caddy uses ACME), writes them all to
# `hosting/caddy/Caddyfile.public`, and adds an `import Caddyfile.public`
# line to `Caddyfile` (idempotent — re-running re-renders Caddyfile.public).
#
# Skipping (blank domain) removes Caddyfile.public and the import line.
#
# Auto-run by `./existential.sh` on first init for the caddy service.
# Re-run manually: ./existential.sh run caddy

set -euo pipefail

# Self-elevate into existential-adhoc so /repo is at /repo and we have curl.
if [[ -z "${IN_CONTAINER:-}" ]]; then
    _D="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    _R="$(cd "$_D/../.." && pwd)"
    exec docker compose -f "${_R}/existential-compose.yml" run --rm -it \
        --entrypoint "" existential-adhoc bash "/repo${_D#"$_R"}/exist.initial.sh"
fi

REPO_DIR=/repo
ENV_EXIST="${REPO_DIR}/.env.shared"
CADDYFILE="${REPO_DIR}/hosting/caddy/Caddyfile"
CADDYFILE_PUBLIC="${REPO_DIR}/hosting/caddy/Caddyfile.public"

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

[ -f "$ENV_EXIST" ] || die "${ENV_EXIST} not found — run ./existential.sh first"
[ -f "$CADDYFILE" ] || die "${CADDYFILE} not found — caddy must be initialized first"

# ── Intro ─────────────────────────────────────────────────────────────────────

CURRENT_DOMAIN=$(env_get "$ENV_EXIST" "EXIST_PUBLIC_DOMAIN")
INTERNAL_DOMAIN=$(env_get "$ENV_EXIST" "EXIST_DOMAIN")
INTERNAL_DOMAIN="${INTERNAL_DOMAIN:-x.internal}"

echo ""
hr
echo "  Caddy — optional public-domain setup"
hr
echo ""
echo "  Default behavior is local-only: every service is served at"
echo "  <slug>.${INTERNAL_DOMAIN} with a cert from Caddy's internal CA."
echo ""
echo "  Opt in to a public domain to ALSO serve each service at"
echo "  <slug>.<your-domain> with real Let's Encrypt certs."
echo ""
echo "  The <slug>.${INTERNAL_DOMAIN} hostnames remain intact either way."
echo ""
echo "  Requirements for public domain to work:"
echo "    1. You own the domain"
echo "    2. <domain> and *.<domain> resolve to your public IP"
echo "    3. Your router forwards :80 and :443 to this machine"
echo "       (:80 is required for the ACME HTTP-01 challenge)"
echo ""
if [ -n "$CURRENT_DOMAIN" ]; then
    echo "  Current value: EXIST_PUBLIC_DOMAIN=${CURRENT_DOMAIN}"
else
    echo "  Current value: EXIST_PUBLIC_DOMAIN=  (local-only)"
fi
echo ""
hr
echo ""
echo "  Enter your public domain (e.g. homelab.example.com)"
echo "  Leave blank to skip / remove public-domain blocks."
echo ""
read -rp "  EXIST_PUBLIC_DOMAIN [${CURRENT_DOMAIN}]: " input
DOMAIN="${input:-$CURRENT_DOMAIN}"

# ── Branch: skip / remove ────────────────────────────────────────────────────

if [ -z "$DOMAIN" ]; then
    echo ""
    echo "  No public domain configured."
    if [ -f "$CADDYFILE_PUBLIC" ]; then
        rm -f "$CADDYFILE_PUBLIC"
        echo "  ✓ Removed ${CADDYFILE_PUBLIC#"$REPO_DIR/"}"
    fi
    # Strip any existing `import Caddyfile.public` line.
    if grep -q '^import Caddyfile\.public' "$CADDYFILE"; then
        sed -i '/^import Caddyfile\.public$/d' "$CADDYFILE"
        echo "  ✓ Removed 'import Caddyfile.public' from Caddyfile"
    fi
    env_set "$ENV_EXIST" "EXIST_PUBLIC_DOMAIN" ""
    echo "  ✓ Set EXIST_PUBLIC_DOMAIN= (blank) in .env.shared"
    echo ""
    echo "  Restart caddy if it was already running:"
    echo "    docker compose -f hosting/caddy/docker-compose.yml restart caddy"
    exit 0
fi

# ── Branch: generate public-domain blocks ────────────────────────────────────

echo ""
echo "  Probing DNS for ${DOMAIN}..."
RESOLVED=$(getent hosts "$DOMAIN" 2>/dev/null | awk '{print $1}' | head -1 || true)
if [ -n "$RESOLVED" ]; then
    echo "    ${DOMAIN} → ${RESOLVED}"
else
    echo "    (could not resolve — Let's Encrypt will not be able to issue certs"
    echo "     until <domain> resolves publicly to your IP)"
fi
echo ""

# Generate Caddyfile.public from the <slug>.{$CADDY_DOMAIN} blocks in Caddyfile.
# The internal blocks use Caddy's literal {$CADDY_DOMAIN} token (resolved at runtime),
# so we match and strip that token, then emit <slug>.<public-domain> blocks.
awk -v domain="$DOMAIN" '
    BEGIN {
        print "# Caddyfile.public — generated by hosting/caddy/exist.initial.sh"
        print "# from the <slug>.{$CADDY_DOMAIN} blocks in Caddyfile. DO NOT edit by hand;"
        print "# re-run ./existential.sh run caddy after changing services."
        print ""
        suffix_re = "\\.\\{\\$CADDY_DOMAIN\\}$"
        in_block = 0
    }
    $2 == "{" && $1 ~ suffix_re {
        host = $1
        sub(suffix_re, "", host)
        print host "." domain " {"
        in_block = 1
        next
    }
    in_block && /^[[:space:]]*tls[[:space:]]+internal[[:space:]]*$/ { next }
    in_block && /^\}[[:space:]]*$/ { print "}"; print ""; in_block = 0; next }
    in_block { print }
' "$CADDYFILE" > "$CADDYFILE_PUBLIC"

BLOCK_COUNT=$(grep -cE '^[a-z].*\{$' "$CADDYFILE_PUBLIC" || true)
echo "  ✓ Wrote ${CADDYFILE_PUBLIC#"$REPO_DIR/"} (${BLOCK_COUNT} public-domain block(s))"

# Idempotently add `import Caddyfile.public` to Caddyfile.
if ! grep -q '^import Caddyfile\.public$' "$CADDYFILE"; then
    printf '\n# Public-domain blocks (managed by hosting/caddy/exist.initial.sh)\nimport Caddyfile.public\n' >> "$CADDYFILE"
    echo "  ✓ Added 'import Caddyfile.public' to Caddyfile"
fi

env_set "$ENV_EXIST" "EXIST_PUBLIC_DOMAIN" "$DOMAIN"
echo "  ✓ Set EXIST_PUBLIC_DOMAIN=${DOMAIN} in .env.shared"

echo ""
hr
echo ""
echo "  Public-domain hostnames generated for:"
sed -n 's/^\([a-z][a-z0-9-]*\)\.'"$(echo "$DOMAIN" | sed 's/\./\\./g')"' \{$/  - https:\/\/\1.'"$DOMAIN"'\//p' "$CADDYFILE_PUBLIC"
echo ""
echo "  Restart caddy to apply:"
echo "    docker compose -f hosting/caddy/docker-compose.yml restart caddy"
echo ""
echo "  Caddy will request certs on first request to each hostname. If a cert"
echo "  request fails (rate limits, DNS, port forwarding), see:"
echo "    docker logs caddy | grep -i acme"
echo ""
