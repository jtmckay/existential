---
service: hosting/caddy
sidebar_position: 5
---

# Caddy

- Source: https://github.com/caddyserver/caddy
- License: [Apache 2.0](https://www.apache.org/licenses/LICENSE-2.0)
- Alternatives: Nginx, Traefik, Nginx Proxy Manager, HAProxy

Reverse proxy — access everything hosted on different machines and ports through a single externally accessible port.

## Turning it on

An add-on: Core reaches its two web apps over Tailscale. Add Caddy for `https://<slug>.<domain>`
names, LAN access without Tailscale, or a name for each of many web add-ons.

```bash
EXIST_IS_HOSTING_CADDY=true          # in .env.shared
./existential.sh && docker compose up -d
```

Every web service you enable then answers at `https://<slug>.<domain>`. `EXIST_DOMAIN` defaults
to `<your-lan-ip-with-dashes>.nip.io`, public wildcard DNS that maps every subdomain back to that
IP, so new services need no DNS change. With Tailscale up, the first run takes the tailnet
address instead (never a MagicDNS name: there is no wildcard under a node). To reach it from
outside the house, see [VPN](./vpn). `nslookup code-server.<domain>` checks a device resolves it.

### Trust its CA once per device

Caddy signs every host with an internal CA that its `exist.initial.sh` mints, at
`hosting/caddy/certs/internal-ca.pem` (gitignored). Install it once on each device:

| | |
|---|---|
| macOS | Keychain Access → import `internal-ca.pem` → Always Trust |
| iOS | AirDrop the `.pem` → Settings → General → VPN & Device Management → trust it |
| Windows | `certutil -addstore -f "ROOT" internal-ca.pem` |
| Android | Settings → Security → Install from storage |
| Linux | `sudo cp internal-ca.pem /usr/local/share/ca-certificates/existential-internal-ca.crt && sudo update-ca-certificates` |

Changed `EXIST_DOMAIN` after the first render? The certificate on disk is for the old one.
Re-mint the leaf (the CA, and every device's trust in it, survives):
`rm hosting/caddy/certs/internal.pem hosting/caddy/certs/internal-key.pem`, then
`./existential.sh && docker compose up -d`.

For names that resolve with the internet down, add [piHole](./pihole) and point your router's DNS
at this machine. For real Let's Encrypt names on a domain you own, with a wildcard record at your
public IP: `./existential.sh run caddy public-domain`.

## Auth at the edge

`firecrawl.<domain>` is the one vhost Caddy gates itself, with a bearer token
(`FIRECRAWL_API_KEY`): self-hosted Firecrawl accepts any api_key — including none — so without
that check it is an open proxy for anyone who can reach Caddy. It **fails closed**: a blank key
matches nothing, so the host answers 401 rather than opening up. That is the pattern to copy if
you gate another host — never a config that errors, because a Caddyfile that fails to load takes
every hostname down, not one.

## Port Binding Note

Ports exposed to the Docker host using `port: 8421:80` bind the host port to the Docker port at `:80`. However, if another container within the Docker network is accessing that container, it will still use `:80` — not `:8421`.

## Privileged Port Error

To allow binding to port 80 without root, add to `/etc/sysctl.conf`:

```
net.ipv4.ip_unprivileged_port_start=80
```

Apply immediately:

```bash
sudo sysctl -w net.ipv4.ip_unprivileged_port_start=80
```
