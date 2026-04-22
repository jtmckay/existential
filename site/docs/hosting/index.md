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

All services connect to the `exist` overlay network with:

- **Overlay driver**: Multi-host communication (Docker Swarm compatible)
- **Attachable**: Standalone containers can join
- **Encrypted**: IPsec encryption between nodes

The network is automatically created when you run `docker compose up`.
