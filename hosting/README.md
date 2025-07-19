# Hosting

### What's important is to have the interface:
- VPN (or public internet hosting) for roaming access

## System OS
- [Proxmox](./proxmox/README.md) (alt: Unraid)

## Container management
- [Docker](./docker/README.md) (+Swarm alt: Kubernetes)
- [Portainer](./portainer/README.md) (alt: Dokku, Coolify)

## External network (access self hosted from the internet)
- VPN is the most secure option (skip caddy/cloudflare)
- [Caddy](./caddy/README.md) (Reverse proxy. Alt: Traefik/Nginx)
- [Cloudflare](./cloudflare/README.md) (alt: any domain manager/DNS/[Ngrok](../graveyard/ngrok/README.md))
