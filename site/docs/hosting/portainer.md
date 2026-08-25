---
sidebar_position: 4
---

# Portainer

- Source: https://github.com/portainer/portainer
- License: [zlib](https://github.com/portainer/portainer/blob/develop/LICENSE) (Community Edition)
- Alternatives: Dockge, Yacht, Lazydocker

Remote Docker container management. Portainer itself also supports Docker Swarm and
Kubernetes, but in this stack it runs as an ordinary compose service on a single host.

## Deployment

Enable it and bring the stack up from the repo root like any other service:

```bash
EXIST_IS_HOSTING_PORTAINER=true    # in .env.shared
./existential.sh && docker compose up -d
```
