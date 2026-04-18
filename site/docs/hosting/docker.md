---
sidebar_position: 3
---

# Docker

- Source: https://github.com/moby/moby
- License: [Apache 2.0](https://www.apache.org/licenses/LICENSE-2.0)
- Alternatives: Podman, Kubernetes, k3s

Install using the [official Docker guide](https://docs.docker.com/engine/install/ubuntu/) (NOT via Snap).

## Network

The `exist` network is automatically created when running `docker compose up`. To create it manually:

```bash
docker network create \
  --driver overlay \
  --attachable \
  --opt encrypted \
  exist
```

## Privileged Port Error

To allow binding to ports like 80 without root, add to `/etc/sysctl.conf`:

```
net.ipv4.ip_unprivileged_port_start=80
```

Apply immediately:

```bash
sudo sysctl -w net.ipv4.ip_unprivileged_port_start=80
```
