---
sidebar_position: 6
---

# Cloudflare

- Source: https://cloudflare.com (managed service)
- License: N/A — proprietary managed SaaS; no self-hosted software is bundled
- Alternatives: Let's Encrypt + self-hosted DNS, Bunny DNS, Route 53

DNS and domain management for external access. Nothing is installed — this page is
the manual half of pointing a domain you own at the stack.

Pick **one** of the two public paths; they are alternatives, not steps:

- **Let's Encrypt (the supported default).** `./existential.sh run caddy public-domain`
  generates a `<slug>.<public-domain>` block per service and lets Caddy get and renew
  the certs itself. Needs the DNS records **DNS-only (grey cloud)** and :80/:443
  forwarded to the box — an orange-clouded record terminates TLS at Cloudflare and
  can swallow the HTTP-01 challenge.
- **Cloudflare proxy + Origin Certificate (below).** Records are **proxied (orange
  cloud)**, so your home IP stays out of DNS and Cloudflare terminates TLS.

## DNS

Create the records you want exposed — by specific subdomain or by
[wildcard](https://developers.cloudflare.com/dns/manage-dns-records/how-to/create-subdomain/).

## SSL certificate

### Set SSL/TLS encryption

1. Go to SSL/TLS for your domain
2. Set encryption to **Full (strict)**

Full (strict) is the only correct setting here: Flexible sends plaintext to your box,
and Full accepts any certificate without validating it. Caddy always presents a real
certificate, so strict costs nothing.

### Generate an Origin Certificate

1. Dashboard → your domain → SSL/TLS → Origin server → Create Certificate
2. Defaults, 15 years
3. Save the certificate to `hosting/caddy/certs/cloudflare.pem` and the key to
   `hosting/caddy/certs/cloudflare-key.pem` (that directory is mounted read-only into
   Caddy at `/etc/caddy/certs/`; nothing in it is tracked by git)
4. Point the `tls` directive at the pair in whichever Caddyfile serves the public
   hostnames:

   ```
   tls /etc/caddy/certs/cloudflare.pem /etc/caddy/certs/cloudflare-key.pem
   ```

   In peer mode that is the front door's `Caddyfile` (start from
   `Caddyfile.frontdoor-public.example`, which ships the same line pointing at
   `public.pem`). On a single host you are hand-managing `hosting/caddy/Caddyfile` —
   do **not** use `run caddy public-domain`, which regenerates `Caddyfile.public`
   from scratch on every run and would overwrite the change. Then
   `docker compose restart caddy` from the repo root.

:::warning One wildcard label only
The default hostnames on an Origin Certificate are `example.com` and `*.example.com`.
A wildcard matches **one** label, so if `EXIST_PUBLIC_DOMAIN` is itself a subdomain
(`homelab.example.com`), `app.homelab.example.com` is **not** covered and Cloudflare
returns a 526. Add `*.homelab.example.com` to the hostname list when creating the
certificate.
:::

An Origin Certificate is signed by Cloudflare's private Origin CA, which browsers do
not trust. It is only valid for traffic arriving through Cloudflare — that is the
point, but it means a proxied record can never be switched to DNS-only without also
switching certificates.

## Before you leave it running

- **Proxying hides your IP from DNS; it does not close the port.** Anyone who learns
  the address reaches Caddy directly and bypasses Cloudflare's WAF and rate limits.
  Restrict :80/:443 to [Cloudflare's IP ranges](https://www.cloudflare.com/ips/) at
  the router or host firewall, or turn on
  [Authenticated Origin Pulls](https://developers.cloudflare.com/ssl/origin-configuration/authenticated-origin-pull/).
- **Backends see Cloudflare's IPs, not your visitors'.** Cloudflare sends the real
  address in `CF-Connecting-IP` and appends it to `X-Forwarded-For`. Caddy ignores
  both unless you tell it which hop to trust, so add a
  [`trusted_proxies`](https://caddyserver.com/docs/caddyfile/options#trusted-proxies)
  global option listing the Cloudflare ranges. Do **not** set it on the local-only
  `<slug>.<EXIST_DOMAIN>` blocks — there is no proxy in front of those, and trusting a
  header nobody strips lets any LAN client spoof its own IP.
- **Only some ports are proxied.** Cloudflare's orange cloud forwards HTTPS on
  443/2053/2083/2087/2096/8443 and nothing else, so a service exposed on an odd host
  port has to go through Caddy.
- **A [Cloudflare Tunnel](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/)
  removes the router step entirely** — `cloudflared` dials out, so no inbound port is
  forwarded, no origin IP is exposed, and the allowlisting above becomes unnecessary.
  It is not wired into this stack; run it yourself if you want it.
