# Hosting

## Overview
#### System OS recommendation
- [Proxmox](./proxmox/README.md) (alt: Unraid)

#### Container management
- [Docker](./docker/README.md)
- [Portainer](./portainer/README.md)

#### External network (access remotely)
- VPN is the most secure option (skip caddy/cloudflare)
- [Caddy](./caddy/README.md) (Reverse proxy. Alt: Traefik/Nginx)
- [Cloudflare](./cloudflare/README.md) (alt: any domain manager/DNS/[Ngrok](../graveyard/ngrok/README.md))

## Existential script
`./existential.sh`
1. Find top-level .env.example file
2. Create .env from .env.example (if .env doesn't exist)
3. Interactively replace EXIST_CLI placeholders in .env
4. Automatically replace other EXIST_* placeholders in .env
5. Source .env to load variables into shell environment
6. Find and create service-level .env files (depth 2)
7. Interactively replace EXIST_CLI in service .env files
8. Automatically replace EXIST_* in service .env files
9. Generate docker-compose.yml from enabled services
10. Report completion summary and thank you

### Enable/disable services
When you enable/disable services you must regenerate the docker-compose.yml to reflect the enabled services. The script will not replace an existing docker-compose.yml, but instead will create a docker-compose.generated.yml that you can copy over the docker-compose.yml if desired. It also generates a `diff` file to help you find the changes, if you want to keep some of the existing customized file.

## Explanation
  1. .env.example

  A comprehensive environment configuration file with:
  - Global settings (enabled services, Docker network, logging)
  - Service-specific configurations organized by category
  - Security settings with placeholders for secrets
  - Clear comments and grouping for easy navigation
  - Default values for common settings

  2. docker-compose.yml

  A master orchestration file that:
  - Uses Docker profiles to control which services deploy
  - Implements shared logging and environment configurations
  - Properly defines service dependencies and health checks
  - Uses NFS volumes for persistent data (via TrueNAS)
  - Organizes services by category matching the project structure
  - Includes the custom exist network configuration

  Key Features:

  - Profile-based deployment: Services can be deployed individually, by category, or all
  together
  - Consistent configuration: Shared logging, timezone, and NAS settings across all services
  - Proper dependencies: Services wait for their databases/dependencies to be healthy
  - Volume management: Mix of local and NFS volumes based on data persistence needs
  - Security: No hardcoded passwords, all sensitive data comes from environment variables

  Usage:

  # Deploy specific services
  docker compose --profile librechat --profile windmill up -d

  # Deploy by category
  docker compose --profile ai --profile automation up -d

  # Deploy everything
  docker compose --profile all up -d
