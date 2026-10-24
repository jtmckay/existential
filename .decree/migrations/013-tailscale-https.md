---
machine: develop
---
# Tailscale is one way to reach the stack, not a prerequisite

## Overview

The docs list Tailscale as a prerequisite and the setup output nags when it isn't running. It
isn't needed: the stack works on the LAN with nothing installed, and remote access can be any
VPN (Tailscale, WireGuard, OpenVPN, Headscale) or local DNS through a piHole on another
server. Recommending one vendor's hosted coordination service by default contradicts "on
hardware you own".

## Outcome

- The prerequisites in `README.md`, `site/docs/getting-started.md` and `site/docs/intro.md`
  are Docker (usable without sudo), a machine, and the repo. Tailscale is not listed.
- The default address story is the LAN: the first run derives `<lan-ip-with-dashes>.nip.io`,
  reachable from devices on the same network with nothing configured.
- Remote access is one short, vendor-neutral section ("Reaching it from outside the house")
  that links to `site/docs/hosting/vpn.md`, which lists the VPN options side by side without
  favouring one.
- Host IP detection behaves as before: when a tailnet address is up, it is still preferred,
  and the MagicDNS warning stays wherever it is relevant. Docs describe that as "if you use
  Tailscale", not as the expected setup.
- The quest run no longer prints a warning when Tailscale isn't running. On a LAN address it
  says the services work from this network, and points at the VPN page for anywhere else.
- Quest `01-network-access` replaces "Put your devices on the tailnet" with the
  vendor-neutral remote-access section.
- The service tour no longer has a Core "Also on your devices" section for Tailscale; Core's
  story on the tour ends with the hosted Core services. The tour's header comment matches.
- `.claude/reference/networking.md` and `templates.md` say Tailscale is optional.

## Constraints

- `_detect_host_ip`'s results don't change for any host.
- No new prerequisite or service replaces Tailscale.

## Acceptance Criteria

- **Given** `README.md`, `site/docs/getting-started.md` and `site/docs/intro.md`
  **When** their prerequisites are read
  **Then** Tailscale is not among them
- **Given** a host with no tailscale binary
  **When** the quest's closing access tip runs with a LAN nip.io domain
  **Then** the output doesn't mention Tailscale and does point at the VPN docs
- **Given** the docs site build
  **When** it runs
  **Then** it succeeds
