---
sidebar_position: 2
---

# Docker Swarm

- Source: https://github.com/moby/moby
- License: [Apache 2.0](https://www.apache.org/licenses/LICENSE-2.0)
- Alternatives: Kubernetes, k3s, Nomad
- Status: RIP — networking was annoying and added complexity for env variables

Multi-server Docker orchestration.

## Features

- **Native Docker Integration**: Built into Docker Engine — no extra tools to install
- **Multi-Host Networking**: Encrypted overlay networks spanning multiple machines
- **Service Scaling**: Scale containers up or down with a single command
- **Rolling Updates & Rollbacks**: Deploy new images with zero downtime and easy rollback
- **Node Placement Constraints**: Pin services to specific nodes via labels
- **Built-In Secrets Management**: Securely distribute credentials to services

## Setup Network

```bash
docker network create \
  --driver overlay \
  --attachable \
  --opt encrypted \
  exist
```

## Setup Swarm (Manager First)

```bash
docker swarm init --advertise-addr <MANAGER-IP>
# Save the output token to add workers
```

Deploy the registry:

```bash
docker stack deploy -c docker-compose.yml registry
```

## Join Swarm (Worker)

Run the join command returned from the manager init step.

## Pin Service to Node

```yaml
deploy:
  placement:
    constraints:
      - node.labels.has_local_ssd == true
```

```bash
# List nodes
docker node ls

# Label a node
docker node update --label-add has_local_ssd=true {hostname}
```
