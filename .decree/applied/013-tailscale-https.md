---
machine: develop
---
# Tailscale is part of Core: real HTTPS, nothing to trust by hand

## Overview

Core's two web apps both need a certificate every device already trusts: code-server's editor
webviews (the markdown preview that shows your graphs) don't run behind a certificate warning,
and the ntfy phone app won't connect to one. A private CA means installing a root certificate
on every phone and laptop, the most technical step a new user would hit. Tailscale issues
publicly trusted Let's Encrypt certificates for a machine's tailnet name, so Core needs no
reverse proxy and no certificate install anywhere.

## Outcome

- Tailscale is part of Core. Getting Started walks through it: installed
  and logged in on the host and on every device that should reach Core. README, Getting
  Started and intro list it with Docker as what Core needs.
- With Tailscale up on the host, `./existential.sh` serves Core over HTTPS on the machine's
  tailnet name with `tailscale serve`: code-server at `https://<machine>.<tailnet>.ts.net` and
  ntfy at `https://<machine>.<tailnet>.ts.net:8443`. The serve config persists across reboots,
  and re-running `./existential.sh` doesn't duplicate it.
- When Tailscale can't serve yet, `./existential.sh` prints the exact steps and carries on
  without failing: enabling MagicDNS and HTTPS certificates in the admin console, and
  `sudo tailscale set --operator=$USER` once, since it never runs sudo itself.
- Core services publish their ports on the host's loopback only; nothing in Core listens on
  the LAN.
- ntfy's base URL and every link the stack sends (ntfy messages, the digest) use the tailnet
  URL.
- The docs say plainly that the tailnet name appears in public certificate transparency logs:
  visible, not reachable.
- A host without Tailscale is outside Core. There, the Caddy add-on provides `https://<slug>.<domain>` hostnames with its
  internal CA (trusted once per device, as its guide explains), on the LAN or any VPN. Host
  IP detection and the nip.io default behave as before for Caddy.
- `.claude/reference/networking.md` describes both paths, and which one Core uses.

## Constraints

- `existential.sh` never runs sudo, and never fails because Tailscale is missing or not yet
  set up.
- No new service in Core.

## Acceptance Criteria

- **Given** a host with Tailscale up and HTTPS enabled for the tailnet
  **When** `./existential.sh` runs twice
  **Then** `tailscale serve status` shows code-server on 443 and ntfy on 8443, once each
- **Given** a host with no tailscale binary
  **When** `./existential.sh` runs
  **Then** it exits 0 and prints that Core needs Tailscale, how to install it, and the Caddy
  add-on as the alternative
- **Given** a Core install
  **When** its published ports are listed
  **Then** each is bound to 127.0.0.1
