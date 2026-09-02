---
sidebar_position: 1
---

# Hosting Overview

## Standard Hosting

Start with [Getting Started](https://existential.company/docs/getting-started)

## Advanced Hosting

### System OS

- [Proxmox](./proxmox) (alt: Unraid)

### Container Management

- [Docker](./docker)
- [Portainer](./portainer)

### External Network (Access Remotely)

- VPN is the most secure option (skip Caddy/Cloudflare)
- [Caddy](./caddy) — Reverse proxy (Alt: Traefik/Nginx)
- [Cloudflare](./cloudflare) — DNS/domain manager

### Networking

All services connect to a single Docker **bridge** network named `exist`, created
automatically by `docker compose up`. Containers reach each other by container name
(`http://ollama:11434`); see [How It Works](../how-it-works) for the full model.

:::warning[Traffic on this network is not encrypted]
A bridge network is single-host and carries plain traffic between containers. It is not an
overlay, there is no IPsec, and it does not span machines. To run services on more than one
box, treat them as [complementary services](../how-it-works) reached over a URL rather than
trying to stretch this network across hosts.
:::

### Observability

- [Prometheus](./prometheus) — Metrics collection (+ Pushgateway for Decree)
- [Loki](./loki) — Log aggregation (+ Alloy for Decree run logs)
- [Grafana](./grafana) — Dashboards over Prometheus and Loki

### Network

- [Pi-hole](./pihole) — DNS ad blocking and DHCP
