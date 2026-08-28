---
name: Network Access
tagline: "Reverse proxy + tailnet — makes every service reachable at https://<slug>.<domain>"
e2e: false
e2e_skip: Requires tailscale enrollment and TLS certificate infrastructure
services:
  - var: EXIST_IS_HOSTING_CADDY
    label: Caddy
---

Caddy fronts every service at `https://<slug>.<domain>`. The only question left
is how that name resolves and how it reaches this machine — and with tailscale
installed (a prerequisite), both are already answered.

── How the address works ─────────────────────────────────────────────────

EXIST_DOMAIN defaults to `<your-tailnet-ip-with-dashes>.nip.io`, filled in for
you on the first run from `tailscale ip -4`. nip.io is public wildcard DNS: it
answers EVERY subdomain by mapping the name back to that IP, so
`https://dashy.${EXIST_DOMAIN}` works on any device with nothing configured.
Because the IP is a tailnet address, only devices on your tailnet can actually
route to it. New services need no DNS change, ever.

There is one trap worth naming: do NOT set EXIST_DOMAIN to a MagicDNS name like
`<node>.ts.net`. MagicDNS resolves that exact node name and nothing beneath it —
there is no wildcard under a node — so every `<slug>.` under it is NXDOMAIN.

── Step 1: Put your devices on the tailnet ───────────────────────────────

Anything that should reach the stack — laptop, phone, tablet — needs to be
logged into the same tailnet as this machine.

1. Install Tailscale: https://tailscale.com/download
2. Log in with the same account you used on this host.
3. Check it worked:  nslookup dashy.${EXIST_DOMAIN}
   (any subdomain works — the wildcard answers them all)

That is the whole network setup. No router changes, no DNS server, no port
forwarding, and nothing exposed to the internet.

── Step 2: Trust Caddy's internal CA ────────────────────────────────────

Caddy fronts every service with TLS using a pinned internal CA minted by
caddy's exist.initial.sh. Install the root cert once per device for a green
padlock everywhere. The CA file is committed to the repo:
  hosting/caddy/certs/internal-ca.pem

On each device that needs to trust it:
  macOS:   Open Keychain Access → import internal-ca.pem → set to Always Trust
  iOS:     AirDrop the .pem → Settings → General → VPN & Device Management → trust it
  Windows: Run: certutil -addstore -f "ROOT" internal-ca.pem
  Android: Settings → Security → Install from storage
  Linux:   sudo cp internal-ca.pem /usr/local/share/ca-certificates/existential-internal-ca.crt
           && sudo update-ca-certificates

If you changed EXIST_DOMAIN after the first render, the cert on disk is for the
OLD domain and every browser will reject it. Re-mint the leaf (the CA, and so
every device that already trusts it, survives):
  rm hosting/caddy/certs/internal.pem hosting/caddy/certs/internal-key.pem
  ./existential.sh && docker compose up -d

── Optional: Local DNS with pihole ──────────────────────────────────────

nip.io means name resolution depends on an internet DNS lookup. Pihole removes
that — one wildcard record (address=/${EXIST_DOMAIN}/${EXIST_LOCAL_HOST_IP})
answers the whole domain locally, so the stack keeps working with the WAN
unplugged. It is an upgrade, not a requirement, and it is what you want if you
prefer a made-up TLD like x.internal over nip.io.

Enable EXIST_IS_HOSTING_PIHOLE=true, then point your router's DNS (usually
under DHCP or LAN, at http://192.168.1.1) at ${EXIST_LOCAL_HOST_IP}. Devices
pick up the new resolver on their next DHCP lease renewal.

── Optional: Second machine (peer mode) ─────────────────────────────────

Running services on a SECOND machine? Keep caddy on this (front-door) host, set
EXIST_PEER_HOST_IP to the other machine's IP, and swap in
hosting/caddy/Caddyfile.frontdoor-lan.example — it forwards every
<slug>.<domain> to the second machine's Caddy. No per-service DNS or port
config needed. For an internet-facing entrypoint (real domain + public certs)
use the -public variant.

── Optional: Public domain (real HTTPS with Let's Encrypt) ──────────────

To also expose services at https://<slug>.yourdomain.com:
  ./existential.sh run caddy public-domain

This generates a Caddyfile.public with ACME-enabled blocks for every
active service. Requires a domain you control with a wildcard DNS record
pointing at your public IP.
