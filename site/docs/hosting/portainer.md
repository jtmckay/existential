---
sidebar_position: 4
---

# Portainer

- Source: https://github.com/portainer/portainer
- License: [zlib](https://github.com/portainer/portainer/blob/develop/LICENSE) (Community Edition)
- Alternatives: Dockge, Yacht, Lazydocker

Remote Docker container management. Works with a single machine, Docker Swarm, or Kubernetes.

## Features

- **Web UI for Docker**: Manage containers, images, volumes, and networks from a browser
- **Stack Deployment**: Deploy and update Docker Compose stacks through the UI
- **Multi-Host Management**: Connect to remote Docker hosts via the Portainer agent
- **Live Logs & Terminal**: Stream container logs and open a terminal in any running container
- **Swarm & Kubernetes Support**: Unified UI across Docker Standalone, Swarm, and Kubernetes
- **Access Control**: User and team permissions in the Business edition

## Deployment

Must be run from a manager node in the Docker Swarm:

```bash
docker stack deploy -c docker-compose.yml portainer
```
