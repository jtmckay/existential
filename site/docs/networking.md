---
sidebar_position: 3
---

# Networking

How a browser reaches the stack: Core over Tailscale, everything else through Caddy, and how to
reach it from outside the house. Inside the stack, containers talk plain HTTP by name on one
Docker network, `exist` ([How It's Built](./how-it-works.md#one-network)).

## Core over Tailscale

code-server's previews and the ntfy phone app both need a certificate every device trusts.
Tailscale issues a Let's Encrypt certificate for the host's tailnet name, so with Tailscale up
every `./existential.sh` runs `tailscale serve`:

```
https://<host>.<tailnet>.ts.net       →  127.0.0.1:42080  (code-server)
https://<host>.<tailnet>.ts.net:8443  →  127.0.0.1:44680  (ntfy)
```

- Both containers publish on loopback only (`EXIST_CORE_BIND=127.0.0.1`), so only your tailnet
  can connect.
- The name is saved as `EXIST_TAILNET_NAME`, which ntfy and the digest's links use. It appears
  in public certificate transparency logs: visible, not reachable.
- If Tailscale can't serve yet, the run prints what is missing and carries on: **MagicDNS** and
  **HTTPS Certificates** on in the [admin console](https://login.tailscale.com/admin/dns), and
  `sudo tailscale set --operator=$USER` once, which it leaves to you.

`tailscale serve` gives one hostname per node, which is why it serves only Core.

## Without Tailscale

code-server and ntfy listen on your network (`EXIST_CORE_BIND=0.0.0.0`, set by each run) at
`http://<host-ip>:42080` and `http://<host-ip>:44680`, behind your login. code-server's previews
(markdown, the machines' graphs) need HTTPS: for those, turn on Caddy.

## Every other app: Caddy

[Caddy](./hosting/caddy.md) ships off. With it on, every app gets `https://<slug>.<domain>`.
`EXIST_DOMAIN` defaults to `<host-ip-with-dashes>.nip.io`, from this host's LAN address:

```
EXIST_LOCAL_HOST_IP=192.168.1.20          (LAN address)
        ↓
EXIST_DOMAIN=192-168-1-20.nip.io   →  https://dashy.192-168-1-20.nip.io
```

- [nip.io](https://nip.io) is public wildcard DNS: `<anything>.<ip>.nip.io` resolves to that
  IP. No DNS setup, and a new app needs no DNS change.
- A LAN address only routes inside your network. Nothing is exposed.
- With Tailscale up, the tailnet IP (`tailscale ip -4`) is used instead, so the names work
  across your tailnet.
- Services read `EXIST_DOMAIN` at container start, so a change applies on the next
  `docker compose up -d`.

:::danger If you use Tailscale, don't use a MagicDNS name
`EXIST_DOMAIN=my-box.tailnet.ts.net` fails: MagicDNS has no wildcard under a node name, so
`dashy.my-box.tailnet.ts.net` doesn't resolve. Use the tailnet **IP** in nip.io form.
:::

Downsides of the default:

- The certificate is from the stack's own CA, so a browser warns until you
  [trust it on that device](./hosting/caddy.md#trust-its-ca-once-per-device).
  [A domain you own](#a-domain-you-own) gets a certificate every device already trusts.
- Without internet, names stop resolving, even on the host. [pihole](./hosting/pihole.md)
  answers them locally.
- nip.io sees your host's IP and each service name you look up.

## A domain you own

With a domain you own, every device trusts `https://<slug>.<domain>` with nothing to install,
and still nothing on your network becomes reachable from outside: the DNS record points at a LAN
address, and the certificate is issued by a DNS challenge, where Let's Encrypt reads a record
from public DNS and never connects to you.

The steps use a subdomain, `home.example.com`, and Cloudflare as the DNS provider.
[acme.sh](https://github.com/acmesh-official/acme.sh) issues the certificate and
[supports most other providers](https://github.com/acmesh-official/acme.sh/wiki/dnsapi).

1. **One DNS record.** A wildcard `A` record at this host's LAN address (`EXIST_LOCAL_HOST_IP`),
   on Cloudflare set to **DNS only**, not proxied:

   ```
   *.home.example.com   A   192.168.1.20
   ```

2. **A certificate.** Make an API token that can edit the zone's DNS (Cloudflare: *My Profile →
   API Tokens → Create Token → Edit zone DNS*), [install acme.sh](https://github.com/acmesh-official/acme.sh#1-how-to-install),
   then from the repo:

   ```bash
   acme.sh --set-default-ca --server letsencrypt
   read -rs CF_Token && export CF_Token      # paste the token and press Enter; nothing is shown
   acme.sh --issue --dns dns_cf -d '*.home.example.com' -d home.example.com
   acme.sh --install-cert -d '*.home.example.com' \
     --fullchain-file "$PWD/hosting/caddy/certs/internal.pem" \
     --key-file       "$PWD/hosting/caddy/certs/internal-key.pem" \
     --reloadcmd      "docker restart caddy"
   acme.sh --install-cronjob
   ```

   Caddy serves whatever certificate is in those two files, and `./existential.sh` leaves one it
   did not mint alone. The cron job renews it about every 60 days.

3. **Point the stack at it:** `EXIST_DOMAIN=home.example.com` in `.env.shared`, then
   `./existential.sh && docker compose up -d`. The old names stop working, so update bookmarks
   and the ntfy app.

A name that doesn't resolve on your network is usually the router's DNS rebind protection, which
drops public answers that point at a private address. Allow the domain there, or answer it
locally with [pihole](./hosting/pihole.md).

## From outside the house

Tailscale already reaches Core from anywhere. For the Caddy names, any VPN back onto your network
works, without exposing a service:

| | What it is | Who runs the coordination | License |
|---|---|---|---|
| [WireGuard](https://www.wireguard.com/) | A kernel-level tunnel; one config file per peer | You | [GPL-2.0](https://github.com/WireGuard/wireguard-linux) |
| [OpenVPN](https://openvpn.net/) | The long-standing TLS-based VPN | You | [GPL-2.0](https://github.com/OpenVPN/openvpn) |
| [Headscale](https://github.com/juanfont/headscale) | A self-hosted coordination server for the Tailscale clients | You | [BSD-3](https://github.com/juanfont/headscale) |
| [Tailscale](https://tailscale.com/) | A WireGuard mesh with clients for every platform | Tailscale's hosted service | [BSD-3](https://github.com/tailscale/tailscale) (clients) |

A [piHole](./hosting/pihole.md) can answer the whole domain locally with one wildcard record, so
names resolve with the internet unplugged. That is name resolution, not reachability.

## Fixes

- **A Caddyfile missing a newly enabled service's block:** copy the block from
  `Caddyfile.exist.Caddyfile` into the rendered `Caddyfile`.
