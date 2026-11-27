---
machine: repo_develop
---
# Core over Tailscale with real HTTPS; every add-on through one Caddy; nothing published to the internet

## Overview

Core's two web apps need a certificate every device already trusts: code-server's webviews
(the preview that shows the graphs) don't run behind a warning, and the ntfy phone app won't
connect to one. A private CA means installing a root certificate on every phone and laptop,
the most technical step a new person would hit. Tailscale issues publicly trusted
certificates for a host's tailnet name, so Core needs no reverse proxy. Add-ons get names
through Caddy, and nothing is ever exposed to the internet.

## Outcome

- **Tailscale is optional and recommended.** With it up on the host, each `./existential.sh`
  serves Core with `tailscale serve`: code-server at `https://<host>.<tailnet>.ts.net`, ntfy at
  `:8443`, persisting across reboots and never duplicated. The name is saved as
  `EXIST_TAILNET_NAME`, used by ntfy's base URL and every link the stack sends.
- When Tailscale can't serve yet, the run prints the exact steps (MagicDNS and HTTPS
  certificates in the admin console; `sudo tailscale set --operator=$USER` once) and carries
  on.
- **Core binds by mode** (`EXIST_CORE_BIND`, set each run): `127.0.0.1` while Tailscale serves
  it, else `0.0.0.0`, so without Tailscale code-server and ntfy are on the LAN at
  `:42080`/`:44680` behind the login.
- **One Caddy, one host**, shipping off: every add-on at `https://<slug>.<domain>`, with
  `EXIST_DOMAIN` defaulting to `<ip-with-dashes>.nip.io` from this host's address (the tailnet
  IP when Tailscale is up, else the LAN IP), and certificates from Caddy's own CA, trusted
  once per device. A certificate in `hosting/caddy/certs/` that the stack did not mint is left
  alone, which is how a domain you own (DNS challenge, no inbound connection) works.
  `Caddyfile.exist.Caddyfile` is the single source of truth for which hostnames exist.
- **Nothing is published to the internet.** There is no peer or front-door mode
  (`EXIST_PEER_HOST_IP`, `Caddyfile.frontdoor-*`), no `run caddy public-domain`, no
  `EXIST_PUBLIC_DOMAIN`. A public hostname is a block a person adds to their own Caddyfile.
- The docs say plainly: the tailnet name appears in certificate transparency logs (visible,
  not reachable); a MagicDNS name is never `EXIST_DOMAIN` (no wildcard under a node); nip.io
  sees the host's IP and each name looked up. The Technical Networking page is the one place
  that explains all of this; `.claude/reference/networking.md` covers the rules.

## Constraints

- `existential.sh` never runs sudo for Tailscale, and never fails because it is missing or not set up.

## Acceptance Criteria

- **Given** a host with Tailscale up and HTTPS enabled
  **When** `./existential.sh` runs twice
  **Then** `tailscale serve status` shows code-server on 443 and ntfy on 8443, once each
- **Given** a host with no tailscale binary
  **When** `./existential.sh` runs
  **Then** it exits 0 and `EXIST_CORE_BIND=0.0.0.0`
- **Given** the repo
  **When** `git grep` runs for `EXIST_PEER_HOST_IP`, `frontdoor` or `EXIST_PUBLIC_DOMAIN`
  outside `archive/`, `.decree/` and `src/test/` (which asserts their absence)
  **Then** nothing is found
