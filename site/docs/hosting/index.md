---
sidebar_position: 1
---

# Hosting

Where the stack runs, beyond the one computer [Getting Started](../getting-started.md) sets up.

## More than one computer

- [Controller and Workers](./controller-and-workers.md): one host keeps your notes, the others
  report to it and lend it what they have.
- [A Separate AI Box](./ai-box.md): llama.cpp, ComfyUI and TTS taking turns on one GPU box.
- [The Host Daemon](./host-daemon.md): the plugins that run on the host itself.
- [Updates](./updates.md): following the release, pinned images, patching Ubuntu.

Services on more than one box are [complementary](../how-it-works.md#core-vs-complementary-services),
reached over a URL: the `exist` Docker network is a plain single-host bridge, not encrypted and
never stretched across hosts.

## The host

- [Proxmox](./proxmox.md): running it in a VM
- [Docker](./docker.md): the engine, and capping its logs
- [Portainer](./portainer.md): container management

## Reaching it

[Networking](../networking.md) covers Tailscale, Caddy names, a domain you own and VPNs.

- [Caddy](./caddy.md): the reverse proxy for every app beyond Core
- [Cloudflare](./cloudflare.md): DNS for a domain you own
- [Pi-hole](./pihole.md): DNS for your network, ad blocking

## Watching it

- [Grafana](./grafana.md): dashboards over Prometheus and Loki
- [Prometheus](./prometheus.md): metrics
- [Loki](./loki.md): logs, decree runs included
- [Uptime-Kuma](./uptime-kuma.md): simple availability checks
