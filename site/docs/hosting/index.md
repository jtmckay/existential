---
sidebar_position: 1
---

# Hosting Overview

## Standard Hosting

Start with [Getting Started](https://existential.company/docs/getting-started)

## Advanced Hosting

### System OS

- [Proxmox](./proxmox.md) (alt: Unraid)

### Container Management

- [Docker](./docker.md)
- [Portainer](./portainer.md)

### External Network (Access Remotely)

- [VPN](./vpn.md) — the most secure option (skip Caddy/Cloudflare)
- [Caddy](./caddy.md) — Reverse proxy (Alt: Traefik/Nginx)
- [Cloudflare](./cloudflare.md) — DNS/domain manager

### Networking

All services connect to a single Docker **bridge** network named `exist`, created
automatically by `docker compose up`. Containers reach each other by container name
(`http://ollama:11434`); see [How It Works](../how-it-works.md) for the full model.

:::warning[Traffic on this network is not encrypted]
A bridge network is single-host and carries plain traffic between containers. It is not an
overlay, there is no IPsec, and it does not span machines. To run services on more than one
box, treat them as [complementary services](../how-it-works.md) reached over a URL rather than
trying to stretch this network across hosts.
:::

### GPU on Another Machine

- [A Separate AI Box](./ai-box.md): llama.cpp, ComfyUI and TTS on one GPU box, with the stack
  pointed at it

### Observability

- [Prometheus](./prometheus.md) — Metrics collection (+ Pushgateway for Decree)
- [Loki](./loki.md) — Log aggregation (+ Alloy for Decree run logs)
- [Grafana](./grafana.md) — Dashboards over Prometheus and Loki
- [Uptime-Kuma](./uptime-kuma.md) — Simple availability monitoring, separate from the
  Prometheus/Grafana stack above

### Network

- [Pi-hole](./pihole.md) — DNS ad blocking and DHCP
