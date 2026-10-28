---
sidebar_position: 7
---

# VPN

For the Caddy add-on (Core uses Tailscale: [Getting Started](../getting-started.md#setup)). On
your network the `<lan-ip-with-dashes>.nip.io` names already work. A VPN gets a phone or laptop
back onto that network from elsewhere, without exposing any service. Any VPN works.

## Options

| | What it is | Who runs the coordination | License |
|---|---|---|---|
| [WireGuard](https://www.wireguard.com/) | A kernel-level tunnel; one config file per peer | You | [GPL-2.0](https://github.com/WireGuard/wireguard-linux) |
| [OpenVPN](https://openvpn.net/) | The long-standing TLS-based VPN; runs on almost anything | You | [GPL-2.0](https://github.com/OpenVPN/openvpn) |
| [Headscale](https://github.com/juanfont/headscale) | A self-hosted coordination server for the Tailscale clients | You | [BSD-3](https://github.com/juanfont/headscale) |
| [Tailscale](https://tailscale.com/) | A WireGuard mesh with clients for every platform | Tailscale's hosted service | [BSD-3](https://github.com/tailscale/tailscale) (clients) |

## Without a VPN: local DNS

If the devices that matter are on your network anyway, a [piHole](./pihole) on another server
can answer the whole domain locally — one wildcard record — so names resolve with the internet
unplugged. That is name resolution, not reachability: it does not reach the stack from outside
the house.

## If you use Tailscale

When a tailnet address is up, the first run prefers it over the LAN one, so
`<tailnet-ip-with-dashes>.nip.io` reaches the stack from every device on your tailnet. Don't set
`EXIST_DOMAIN` to a MagicDNS name (`<node>.ts.net`): MagicDNS answers exact node names only, so
every `<slug>.` under it fails to resolve. See
[Hostnames that just work](../how-it-works.md#hostnames-that-just-work).
