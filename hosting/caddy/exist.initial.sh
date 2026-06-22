#!/usr/bin/env bash
# caddy — pre-startup init: stable local TLS cert for *.<EXIST_DOMAIN>
#
# `tls internal` works but Caddy auto-rotates its leaf certs (~12h) and the CA
# lives in the caddy_data volume — if that volume is wiped or doesn't persist,
# the whole trust chain changes and every device (notably the ntfy mobile app)
# must be re-trusted. Instead we mint one long-lived cert here, on the host,
# stored in hosting/caddy/certs/ (bind-mounted into caddy at
# /etc/caddy/certs/). The Caddyfile loads it with
# `import internal_tls` instead of `tls internal`, so the served cert is a fixed
# file on disk — it cannot change across reboots or volume wipes.
#
# Idempotent, no sentinel: if the leaf key already exists we do nothing. To
# rotate (e.g. after 825 days), delete internal-key.pem and re-run
# ./existential.sh run — the CA is untouched, so devices stay trusted. An
# advanced user pointing EXIST_DOMAIN at a real domain can simply drop their own
# valid cert in as internal.pem/internal-key.pem; the skip below leaves it alone.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# openssl is a host tool; nothing to do inside the adhoc container.
if [[ "${IN_CONTAINER:-}" == "1" ]]; then
    exit 0
fi

# Base domain for the wildcard cert (matches Caddy's <slug>.<domain> blocks).
ENV_SHARED="$SCRIPT_DIR/../../.env.shared"
EXIST_DOMAIN="$(grep -E '^EXIST_DOMAIN=' "$ENV_SHARED" 2>/dev/null | head -1 | cut -d= -f2-)"
EXIST_DOMAIN="${EXIST_DOMAIN:-x.internal}"

CERT_DIR="$SCRIPT_DIR/certs"                # mounted at /etc/caddy/certs/
CA_KEY="$CERT_DIR/internal-ca-key.pem"
CA_CRT="$CERT_DIR/internal-ca.pem"          # ← install THIS on each device, once
LEAF_KEY="$CERT_DIR/internal-key.pem"
LEAF_CRT="$CERT_DIR/internal.pem"
CA_BUNDLE="$CERT_DIR/ca-bundle.pem"         # system roots + internal CA, for OIDC apps

# Emit a combined CA bundle: the host's public root store + our internal CA. OIDC
# apps (mealie, vikunja) do server-side discovery/token exchange against
# https://authelia.<domain>, served with the internal CA — but they also make
# public-internet TLS calls (recipe scraping, etc.). Pointing their SSL_CERT_FILE at
# the internal CA *alone* would break public TLS, so they need this superset bundle.
# Idempotent: regenerate only if missing or older than its inputs. Caddy owns the
# internal CA, so it owns this artifact too (see AUTHELIA_PHASE2.md §2).
emit_ca_bundle() {
    local host=""
    for f in /etc/ssl/certs/ca-certificates.crt /etc/pki/tls/certs/ca-bundle.crt /etc/ssl/cert.pem; do
        [[ -f "$f" ]] && { host="$f"; break; }
    done
    if [[ -z "$host" ]]; then
        echo "[caddy] No system CA bundle found on host — skipping ca-bundle.pem. OIDC apps that" >&2
        echo "[caddy] must trust the internal CA will need it; see AUTHELIA_PHASE2.md §2." >&2
        return 0
    fi
    [[ -f "$CA_CRT" ]] || return 0
    if [[ -f "$CA_BUNDLE" && "$CA_BUNDLE" -nt "$CA_CRT" && "$CA_BUNDLE" -nt "$host" ]]; then
        return 0  # up to date
    fi
    cat "$host" "$CA_CRT" > "$CA_BUNDLE"
    chmod 644 "$CA_BUNDLE"
    echo "[caddy] Wrote combined CA bundle (system roots + internal CA) → $CA_BUNDLE"
}

# Already minted (or user-supplied) — leave the existing cert (and any device
# trust) alone, but still (re)emit the combined CA bundle in case it's missing/stale.
if [[ -f "$LEAF_KEY" && -f "$LEAF_CRT" && -f "$CA_CRT" ]]; then
    echo "[caddy] Internal *.${EXIST_DOMAIN} cert present — skipping."
    emit_ca_bundle
    exit 0
fi

if ! command -v openssl >/dev/null 2>&1; then
    echo "[caddy] openssl not found on host — install it, then re-run ./existential.sh run." >&2
    exit 1
fi

echo "[caddy] Minting stable *.${EXIST_DOMAIN} cert into hosting/caddy/certs/ ..."

cnf="$(mktemp)"
trap 'rm -f "$cnf" "$CERT_DIR/internal.csr"' EXIT
cat > "$cnf" <<EOF
[req]
distinguished_name = req
[v3]
subjectAltName   = @alt
basicConstraints = CA:FALSE
keyUsage         = digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
[alt]
DNS.1 = *.${EXIST_DOMAIN}
DNS.2 = ${EXIST_DOMAIN}
EOF

# CA: 10 years. This is what you install on devices; it long-outlives the leaf.
if [[ ! -f "$CA_KEY" || ! -f "$CA_CRT" ]]; then
    openssl genrsa -out "$CA_KEY" 4096
    openssl req -x509 -new -nodes -key "$CA_KEY" -sha256 -days 3650 \
        -subj "/CN=Existential Internal CA" -out "$CA_CRT"
fi

# Leaf: 825 days — the max iOS/macOS accept for a server cert even from a
# privately-installed CA. Re-mint before it expires (CA stays put).
openssl genrsa -out "$LEAF_KEY" 2048
openssl req -new -key "$LEAF_KEY" -subj "/CN=*.${EXIST_DOMAIN}" -out "$CERT_DIR/internal.csr"
openssl x509 -req -in "$CERT_DIR/internal.csr" -CA "$CA_CRT" -CAkey "$CA_KEY" \
    -CAcreateserial -days 825 -sha256 \
    -extfile "$cnf" -extensions v3 -out "$LEAF_CRT"

chmod 600 "$CA_KEY" "$LEAF_KEY"
chmod 644 "$CA_CRT" "$LEAF_CRT"

emit_ca_bundle

echo "[caddy] Done. Install the CA on each device (phone for ntfy, laptops):"
echo "[caddy]     $CA_CRT"
echo "[caddy] It is valid 10 years; the leaf auto-loads via the Caddyfile's import internal_tls."
