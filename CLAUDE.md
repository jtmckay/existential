# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Existential is a curated homelab stack combining AI tools, workflow automation, note-taking, file management, and productivity applications. All services are deployed as Docker containers within a custom Docker network named `exist`.

## Directory Structure

- **ai/** - AI tools (LibreChat, Ollama, Whisper, vllm, Chatterbox)
- **services/** - Core applications (Decree, Logseq, NocoDB, ntfy, Vikunja, etc.)
- **nas/** - Storage (MinIO, Nextcloud, Redis, OnlyOffice)
- **hosting/** - Infrastructure (Caddy, Portainer, Proxmox, Uptime-Kuma, VPN)
- **automations/** - Decree working directory (config.yml, routines, cron, inbox)
- **src/** - Shell scripts and setup tools
- **graveyard/** - Archived/alternative solutions
- **site/** - Docusaurus documentation site

## Setup

### Full setup (first run)
```bash
./existential.sh
```

This will:
1. Find all `.example` files and create counterparts (skips existing; directories first, then files)
2. Replace `EXIST_` placeholders interactively (`EXIST_CLI`) or automatically (passwords, hex keys, UUIDs) — reads `EXIST_DEFAULT_*` values from root `.env.exist`
3. Merge enabled services into a unified `docker-compose.yml` via the existential-adhoc container
4. Generate a master `.env` at the repo root by merging `.env.exist` with all enabled service `.env` files

### Targeted commands
```bash
./existential.sh --force          # Regenerate existing files too
./existential.sh examples         # Only process .example files
./existential.sh compose          # Only regenerate docker-compose.yml and master .env
./existential.sh setup gmail      # Gmail OAuth setup
./existential.sh setup rclone     # Configure remote file storage
./existential.sh test             # Run test suite
```

### Manual service setup
```bash
cp services/foo/.env.example services/foo/.env
# edit .env, then:
docker compose up -d
```

## Placeholder System

| Placeholder | Behavior |
|---|---|
| `EXIST_CLI` | Prompts user for input during setup |
| `EXIST_24_CHAR_PASSWORD` | Generates a unique 24-character password per instance |
| `EXIST_32_CHAR_HEX_KEY` | Generates a unique 32-character hex key per instance |
| `EXIST_64_CHAR_HEX_KEY` | Generates a unique 64-character hex key per instance |
| `EXIST_TIMESTAMP` | Current timestamp (`YYYYMMDD_HHMMSS`) |
| `EXIST_UUID` | UUID |
| `EXIST_DEFAULT_*` | Value of matching variable from root `.env.exist` |

## Service Enablement

Services are toggled via `EXIST_ENABLE_*=true/false` in the root `.env.exist`. After changing, regenerate the compose file:

```bash
./existential.sh compose
```

The compose merge is handled by `src/generate-compose.py` (runs in the `existential-adhoc` container using `python3-yaml`). It reads `EXIST_ENABLE_*` from `.env.exist`, discovers `docker-compose.yml` files at depth 2 (generated from `.example` counterparts), adjusts relative paths to be correct from the repo root, and merges services/volumes/networks. It also generates a master `.env` by merging `.env.exist` with all enabled service `.env` files — this is auto-loaded by Docker Compose for variable substitution. Before writing, the previous `docker-compose.yml` is archived as `docker-compose-<timestamp_ms>.yml`.

## Decree (Automations)

Decree is the automation engine. Its working directory is `automations/` (mounted into the container at `/work/.decree`).

- **`automations/config.yml`** - Routine configuration (enabled/disabled)
- **`automations/routines/`** - Automation scripts
- **`automations/cron/`** - Scheduled triggers
- **`automations/setup/`** - Integration setup scripts (run via adhoc container)
- **`services/decree/`** - Docker service definition, secrets, webhook

Integration setup always goes through `./existential.sh setup <name>`, which runs scripts via the `existential-adhoc` container (profile `adhoc` in `existential-compose.yml` at the repo root).

## src/ Scripts

- **`generate-compose.py`** - Merges enabled services into docker-compose.yml (Python, runs in adhoc container)
- **`setup/gmail-sync.sh`** - Gmail OAuth setup
- **`setup/rclone.sh`** - rclone remote configuration
- **`test/run-all.sh`** - Test suite orchestrator
- **`test/test-syntax.sh`** - Syntax check all src/ scripts
- **`test/test-gmail.sh`** - Validate Gmail credentials
- **`test/test-rclone.sh`** - Test rclone remote connectivity
- **`run_initial_setup.sh`** - Post-startup service initialization (Vikunja, Windmill)
- **`create_vikunja_user.sh`** / **`create_windmill_admin.sh`** - Service-specific init scripts

## Architecture

- Each service has its own `docker-compose.yml` and `.env` file
- All services connect to the `exist` bridge network
- Secrets are stored in `services/<name>/secrets/` (gitignored)
- The `existential-adhoc` container (profile: `adhoc`) is used for any setup task requiring non-standard tools — it mounts `src/` at `/src` and the repo at `/repo`
- Documentation lives in `site/` (Docusaurus)

## Testing Services
```bash
docker ps | grep <service_name>   # Check status
docker logs <container_name>      # View logs
./existential.sh test             # Run integration test suite
```
