---
name: Network
tagline: "Caddy — https://<slug>.<domain> for every service, on the LAN or any VPN"
e2e: true
services:
  - var: EXIST_IS_HOSTING_CADDY
    label: Caddy (TLS + hostnames)
done:
  env:
    - EXIST_DOMAIN
  files:
    - hosting/caddy/certs/internal-ca.pem
---

An add-on, not part of Core: Core reaches its two web apps over Tailscale's own
HTTPS. Add Caddy when you want `https://<slug>.<domain>` hostnames, LAN access
without Tailscale, or a name for each of many web add-ons.

── What to do ────────────────────────────────────────────────────────────

  1. Enable it (the picker you just came from does this):
       EXIST_IS_HOSTING_CADDY=true

  2. Render and start:
       ./existential.sh
       docker compose up -d

  3. Every web service you enable now answers at
     https://<slug>.${EXIST_DOMAIN}, e.g. https://code-server.${EXIST_DOMAIN}.
     For one page that links to all of them, add Dashy (the **Monitoring**
     quest).

── How the address works ─────────────────────────────────────────────────

EXIST_DOMAIN defaults to `<your-lan-ip-with-dashes>.nip.io`, filled in for you
on the first run. nip.io is public wildcard DNS: it answers EVERY subdomain by
mapping the name back to that IP, so `https://code-server.${EXIST_DOMAIN}` works on
any device on this network with nothing configured. New services need no DNS
change, ever.

If you use Tailscale and it is up, the first run takes the tailnet address
(`tailscale ip -4`) instead, so the same names work from every device on your
tailnet. In that case, do NOT set EXIST_DOMAIN to a MagicDNS name like
`<node>.ts.net`. MagicDNS resolves that exact node name and nothing beneath it —
there is no wildcard under a node — so every `<slug>.` under it is NXDOMAIN.

── Reaching it from outside the house ────────────────────────────────────

Nothing here faces the internet, and nothing needs to. To reach the stack from
elsewhere, put your devices on a VPN back to this network (WireGuard, OpenVPN,
Tailscale, Headscale), or answer the domain with a piHole on another server.
The options, side by side:
  https://existential.company/docs/hosting/vpn

Check a device can resolve it:  nslookup code-server.${EXIST_DOMAIN}
(any subdomain works — the wildcard answers them all)

── Trust Caddy's internal CA ─────────────────────────────────────────────

Caddy fronts every service with TLS using a pinned internal CA minted by
caddy's exist.initial.sh. Install the root cert once per device for a green
padlock everywhere. The CA file is generated on this host (gitignored):
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

── Optional: Local DNS with pihole ───────────────────────────────────────

nip.io means name resolution depends on an internet DNS lookup. Pihole removes
that — one wildcard record (address=/${EXIST_DOMAIN}/${EXIST_LOCAL_HOST_IP})
answers the whole domain locally, so the stack keeps working with the WAN
unplugged. It is an upgrade, not a requirement, and it is what you want if you
prefer a made-up TLD like x.internal over nip.io.

Enable EXIST_IS_HOSTING_PIHOLE=true, then point your router's DNS (usually
under DHCP or LAN, at http://192.168.1.1) at ${EXIST_LOCAL_HOST_IP}. Devices
pick up the new resolver on their next DHCP lease renewal.

── Optional: Second machine (peer mode) ──────────────────────────────────

Running services on a SECOND machine? Keep caddy on this (front-door) host, set
EXIST_PEER_HOST_IP to the other machine's IP, and swap in
hosting/caddy/Caddyfile.frontdoor-lan.example — it forwards every
<slug>.<domain> to the second machine's Caddy. No per-service DNS or port
config needed. For an internet-facing entrypoint (real domain + public certs)
use the -public variant.

── Optional: Public domain (real HTTPS with Let's Encrypt) ───────────────

To also expose services at https://<slug>.yourdomain.com:
  ./existential.sh run caddy public-domain

This generates a Caddyfile.public with ACME-enabled blocks for every
active service. Requires a domain you control with a wildcard DNS record
pointing at your public IP.
