#!/usr/bin/env bash
# caddy — pre-startup init: stable local TLS cert for *.internal
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
# ./existential.sh run — the CA is untouched, so devices stay trusted.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# openssl is a host tool; nothing to do inside the adhoc container.
if [[ "${IN_CONTAINER:-}" == "1" ]]; then
    exit 0
fi

CERT_DIR="$SCRIPT_DIR/certs"                # mounted at /etc/caddy/certs/
CA_KEY="$CERT_DIR/internal-ca-key.pem"
CA_CRT="$CERT_DIR/internal-ca.pem"          # ← install THIS on each device, once
LEAF_KEY="$CERT_DIR/internal-key.pem"
LEAF_CRT="$CERT_DIR/internal.pem"

# Already minted — leave the existing cert (and any device trust) alone.
if [[ -f "$LEAF_KEY" && -f "$LEAF_CRT" && -f "$CA_CRT" ]]; then
    echo "[caddy] Internal *.internal cert present — skipping."
    exit 0
fi

if ! command -v openssl >/dev/null 2>&1; then
    echo "[caddy] openssl not found on host — install it, then re-run ./existential.sh run." >&2
    exit 1
fi

echo "[caddy] Minting stable *.internal cert into hosting/caddy/certs/ ..."

cnf="$(mktemp)"
trap 'rm -f "$cnf" "$CERT_DIR/internal.csr"' EXIT
cat > "$cnf" <<'EOF'
[req]
distinguished_name = req
[v3]
subjectAltName   = @alt
basicConstraints = CA:FALSE
keyUsage         = digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
[alt]
DNS.1 = *.internal
DNS.2 = internal
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
openssl req -new -key "$LEAF_KEY" -subj "/CN=*.internal" -out "$CERT_DIR/internal.csr"
openssl x509 -req -in "$CERT_DIR/internal.csr" -CA "$CA_CRT" -CAkey "$CA_KEY" \
    -CAcreateserial -days 825 -sha256 \
    -extfile "$cnf" -extensions v3 -out "$LEAF_CRT"

chmod 600 "$CA_KEY" "$LEAF_KEY"
chmod 644 "$CA_CRT" "$LEAF_CRT"

echo "[caddy] Done. Install the CA on each device (phone for ntfy, laptops):"
echo "[caddy]     $CA_CRT"
echo "[caddy] It is valid 10 years; the leaf auto-loads via the Caddyfile's import internal_tls."
