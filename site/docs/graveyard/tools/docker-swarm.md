---
sidebar_position: 2
---

# Docker Swarm

- Source: https://github.com/moby/moby
- License: [Apache 2.0](https://www.apache.org/licenses/LICENSE-2.0)
- Alternatives: Kubernetes, k3s, Nomad
- Status: RIP — networking was annoying and added complexity for env variables

Multi-server Docker orchestration.

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
