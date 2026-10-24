---
name: Access
tagline: Tailscale on the host and your devices — real HTTPS to Core, nothing to trust by hand
e2e: false
e2e_skip: Tailscale runs on the host, not in a container, so there is nothing to bring up
---

The access slice of Core. It has no container: Tailscale runs on the host, and
on every device that should reach Core. Its certificates are publicly trusted,
so code-server and the ntfy phone app work with no reverse proxy and no root
certificate to install anywhere.

── What to do ────────────────────────────────────────────────────────────

  1. Install Tailscale on this host and log in:
       https://tailscale.com/download

  2. In the Tailscale admin console, under DNS, turn on MagicDNS and HTTPS
     certificates.

  3. Install Tailscale on your phone and laptop, logged into the same tailnet.

Core then answers on this machine's tailnet name:

  code-server   https://<machine>.<tailnet>.ts.net
  ntfy          https://<machine>.<tailnet>.ts.net:8443

That name appears in public certificate transparency logs: visible, not
reachable. Only devices on your tailnet can connect.

── No Tailscale? ─────────────────────────────────────────────────────────

A host without Tailscale is outside Core. The **Network** quest adds Caddy:
`https://<slug>.<domain>` hostnames with its own CA, trusted once per device,
on the LAN or over any VPN.
