---
sidebar_position: 4
---

# Portainer

- Source: https://github.com/portainer/portainer
- License: [zlib](https://github.com/portainer/portainer/blob/develop/LICENSE) (Community Edition)
- Alternatives: Dockge, Yacht, Lazydocker

Remote Docker container management. Works with a single machine, Docker Swarm, or Kubernetes.

## Deployment

Must be run from a manager node in the Docker Swarm:

```bash
docker stack deploy -c docker-compose.yml portainer
```
