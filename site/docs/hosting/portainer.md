---
sidebar_position: 4
---

# Portainer

- Source: https://github.com/portainer/portainer
- License: [zlib](https://github.com/portainer/portainer/blob/develop/LICENSE) (Community Edition)
- Alternatives: Dockge, Yacht, Lazydocker
- UI: `https://portainer.<domain>`
- Credentials: `admin` / `EXIST_PASSWORD` (seeded at first boot from `.env.shared`)

Remote Docker container management. Portainer itself also supports Docker Swarm and
Kubernetes, but in this stack it runs as an ordinary compose service on a single host.

Portainer mounts the Docker socket, which is root-equivalent on the host: anyone who can log
into Portainer can start a privileged container and own the machine. Treat the admin password
as a root password, and don't expose `portainer.<domain>` beyond the LAN/Tailscale.

## Deployment

Enable it and bring the stack up from the repo root like any other service:

```bash
EXIST_IS_HOSTING_PORTAINER=true    # in .env.shared
./existential.sh && docker compose up -d
```
