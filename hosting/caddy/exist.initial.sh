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
# ./existential.sh run — the CA is untouched, so devices stay trusted.
#
# The skip below is also the supported path to a REAL certificate: point
# EXIST_DOMAIN at a domain you own, issue a wildcard cert over the DNS-01
# challenge, and drop it in as internal.pem/internal-key.pem — this script then
# leaves it alone. DNS-01 needs no inbound connectivity and no public A record
# (Let's Encrypt reads a TXT record from public DNS, it never connects to you),
# so pihole can still resolve the domain entirely on-LAN. See
# site/docs/how-it-works.md, "Owned domain without exposing your network".
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

# Already minted (or user-supplied) — but only skip if the existing leaf actually
# covers the CURRENT domain. EXIST_DOMAIN is meant to be the one knob you change
# to move the stack (nip.io → a LAN name → a domain you own): everything else
# follows it, because the Caddyfile reads {$CADDY_DOMAIN} at runtime and .env /
# dashy-conf.yml are regenerated every render. The cert was the one thing that
# did not, so a stale `*.x.internal` leaf — minted on a first run that happened
# before EXIST_DOMAIN was set — survived forever, and every browser rejected the
# hostname no matter how many times the domain was corrected.
#
# A leaf we did NOT mint is never touched: that is the documented drop-in path
# for a real DNS-01 wildcard (see the header). We recognise ours by its issuer,
# so a user-supplied cert is left alone even when its SANs disagree — we only say
# so.
if [[ -f "$LEAF_KEY" && -f "$LEAF_CRT" && -f "$CA_CRT" ]]; then
    leaf_sans="$(openssl x509 -in "$LEAF_CRT" -noout -ext subjectAltName 2>/dev/null || true)"
    leaf_issuer="$(openssl x509 -in "$LEAF_CRT" -noout -issuer 2>/dev/null || true)"

    if [[ "$leaf_sans" == *"DNS:*.${EXIST_DOMAIN}"* ]]; then
        echo "[caddy] Internal *.${EXIST_DOMAIN} cert present — skipping."
        exit 0
    fi

    if [[ "$leaf_issuer" != *"Existential Internal CA"* ]]; then
        echo "[caddy] NOTE — ${LEAF_CRT##*/} is not ours (issuer:${leaf_issuer#*issuer=})" >&2
        echo "[caddy]        and does not cover *.${EXIST_DOMAIN}. Leaving it alone." >&2
        echo "[caddy]        Replace it yourself, or delete it to have one minted." >&2
        exit 0
    fi

    # Ours, and for the wrong domain: re-mint the LEAF only. The CA is untouched,
    # so any device that already trusts it stays trusted across the move.
    echo "[caddy] Existing leaf covers ${leaf_sans#*DNS:} — re-minting for *.${EXIST_DOMAIN}."
    rm -f "$LEAF_KEY" "$LEAF_CRT"
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

echo "[caddy] Done. Install the CA on each device (phone for ntfy, laptops):"
echo "[caddy]     $CA_CRT"
echo "[caddy] It is valid 10 years; the leaf auto-loads via the Caddyfile's import internal_tls."
