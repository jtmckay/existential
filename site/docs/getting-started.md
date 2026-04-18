---
sidebar_position: 2
---

# Getting Started

## Prerequisites

- [Docker](https://www.docker.com/get-started/)
- A machine to host the services (see [Hosting](./hosting/))

## Setup

```bash
./existential.sh
```

This will:

1. Find all `.example` files and create non-example counterparts (directories first, then files)
2. Prompt for any `EXIST_CLI` placeholder values interactively
3. Auto-generate passwords, keys, and UUIDs for other placeholders
4. Generate a unified `docker-compose.yml` from all enabled services
5. Generate a master `.env` by merging `.env.exist` with all enabled service `.env` files

## Enable/Disable Services

Edit `.env.exist` and set services to `true` or `false`:

```bash
EXIST_ENABLE_AI_OLLAMA=true
EXIST_ENABLE_SERVICES_DECREE=true
EXIST_ENABLE_SERVICES_NOCODB=false
```

Then regenerate the compose file (already done during initial setup above):

```bash
./existential.sh compose
```

## Deploy

```bash
docker compose up -d
```

## Integrations

Some services require additional OAuth or configuration steps:

```bash
./existential.sh setup gmail    # Gmail OAuth
./existential.sh setup rclone   # Remote file storage
```

See [Integrations](./integrations/) for setup details, or [Scripts](./scripts) for the full CLI reference.
