---
sidebar_position: 2
---

# Getting Started

## Prerequisites

- [Docker](https://www.docker.com/get-started/)
- [Tailscale](https://tailscale.com/download), logged in on this machine and on every
  device that should reach the stack
- A machine to host the services (see [Hosting](./hosting/))
- Git clone the repo
  ```
  git clone https://github.com/jtmckay/existential.git
  cd existential
  ```

## Setup

```bash
./existential.sh
```

This will:

1. Find all `.example` files and create non-example counterparts (directories first, then files)
2. Prompt for any `EXIST_CLI` placeholder values interactively
3. Auto-generate passwords, keys, and UUIDs for other placeholders
4. Generate a unified `docker-compose.yml` from all enabled services
5. Generate a master `.env` by merging `.env.shared` with all enabled service `.env` files

It also fills in `EXIST_LOCAL_HOST_IP` from `tailscale ip -4` (falling back to your LAN address
if tailscale isn't running) and derives `EXIST_DOMAIN` as `<that-ip-with-dashes>.nip.io`. nip.io
is public wildcard DNS, so every `https://<slug>.<domain>` resolves on any device with nothing
configured — while the tailnet address means only your own devices can route to it. No DNS
server, no router changes, no ports open to the internet.

:::warning
Don't set `EXIST_DOMAIN` to a MagicDNS name like `my-box.tailnet.ts.net`. MagicDNS resolves that
exact node name and nothing beneath it, so every `<slug>.` under it fails to resolve. Use the
tailnet **IP** in nip.io form — tailscale carries the traffic, nip.io supplies the wildcard.
:::

## Enable/Disable Services

Edit `.env.shared` and set services to `true` or `false`:

```bash
EXIST_IS_AI_OLLAMA=true
EXIST_IS_SERVICES_DECREE=true
EXIST_IS_SERVICES_NOCODB=false
```

Then re-run the setup script to re-render and regenerate the compose file:

```bash
./existential.sh
```

## Deploy

```bash
docker compose up -d
```

## Integrations

Some services require additional OAuth or configuration steps:

```bash
./existential.sh run gmail    # Gmail OAuth
./existential.sh run rclone   # Remote file storage
```

See [Integrations](./integrations/) for setup details. For the full command list, run `./existential.sh run` with no arguments — it prints every available action.
