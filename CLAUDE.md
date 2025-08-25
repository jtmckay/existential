# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Existential is a curated homelab stack combining AI tools, workflow automation, note-taking, file management, and productivity applications. All services are deployed as Docker containers within a custom Docker network named `exist`.

## Common Development Tasks

### Setup New Service
1. Copy `.env.example` to `.env` in the service directory: `cp .env.example .env`
2. Fill in required environment variables
3. Ensure the Docker network exists: `docker network create exist --subnet=172.18.0.0/24`
4. Deploy the service: `docker-compose up -d`

### Testing Services
- Check service status: `docker ps | grep <service_name>`
- View logs: `docker logs <container_name>`
- Access service: Services are exposed on their configured ports (e.g., Windmill on 8800)

## Architecture

The project follows a modular architecture with services organized into categories:

- **ai/** - AI tools (LibreChat, Ollama, Whisper)
- **services/** - Core applications (Windmill, Logseq, NocoDB, etc.)
- **nas/** - Storage solutions (MinIO, Nextcloud, Redis)
- **hosting/** - Infrastructure tools (Caddy, Portainer, Uptime-Kuma)
- **graveyard/** - Archived/alternative solutions

### Key Architectural Patterns

1. **Docker Compose Structure**: Each service has its own `docker-compose.yml` with:
   - Custom logging configuration using x-logging anchors
   - Connection to the `exist` network
   - Environment variables from `.env` files
   - Health checks for dependent services

2. **Network Configuration**: All services connect to the external Docker network `exist` (172.18.0.0/24)

3. **Volume Management**: Services use either local volumes or NFS mounts to TrueNAS for persistent storage

4. **Service Dependencies**: Services wait for their dependencies using health checks (e.g., Windmill waits for PostgreSQL)

## Core Services

### Workflow Automation
- **Windmill** (port 8800): Primary workflow automation platform supporting Python, TypeScript, Go, Bash, and SQL scripts

### AI Stack
- **LibreChat**: Interface for RAG with notes/digital context
- **Ollama**: General AI model hosting
- **Whisper**: Audio transcription service

### Data Management
- **NocoDB**: Low-code database/spreadsheet platform
- **MinIO**: S3-compatible object storage for file triggers
- **Redis**: Caching and message queue

### Note Taking & Tasks
- **Logseq**: Primary note-taking application
- **Vikunja**: Task management system
- **ntfy**: Notification service

## Deployment Notes

- Services require TrueNAS for NFS volume mounts (configured via `TRUENAS_SERVER_ADDRESS` and `TRUENAS_CONTAINER_PATH`)
- External access can be configured through Caddy reverse proxy or VPN
- Use Portainer for remote container management
- Uptime-Kuma monitors service availability

## Common Patterns

### Environment Variables
Most services use these common variables:
- `LOG_MAX_SIZE`: Log rotation size (default: "20m")
- `LOG_MAX_FILE`: Number of log files to keep (default: "10")
- Service-specific credentials and secrets

### Service Initialization
Many services include init containers that:
- Wait for dependencies to be ready
- Create initial admin users
- Configure default settings

### Inter-Service Communication
Services communicate within the Docker network using container names as hostnames (e.g., `http://windmill_server:8000`).