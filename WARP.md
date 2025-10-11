# WARP.md

This file provides guidance to WARP (warp.dev) when working with code in this repository.

## Project Overview

Existential is a curated homelab stack combining AI tools, workflow automation, note-taking, file management, and productivity applications. All services are deployed as Docker containers within a custom Docker network named `exist`. The project emphasizes self-actualization through comprehensive personal productivity tools.

## 🚀 Essential Commands

### Complete Environment Setup
```bash
# Configure entire environment in one command
./existential.sh

# Process only environment files
./existential.sh env-only

# Process specific file patterns
./existential.sh pattern '*.yml.example'

# Show available file types to process
./existential.sh types
```

### Service Management
```bash
# Show service status
./existential.sh services status

# Enable/disable specific services
./existential.sh services enable mealie
./existential.sh services disable windmill

# Generate docker-compose configuration
./existential.sh generate-compose
```

### Container Operations
```bash
# Start all configured services
docker compose up -d

# View service status
docker compose ps

# View logs for specific service
docker logs <container_name>

# Stop all services
docker compose down

# Initial setup after containers start
./automations/existential/run_initial_setup.sh
```

## 🏗️ Architecture & Structure

### Service Categories
The project is organized into distinct service categories:

- **ai/** - AI tools (LibreChat with RAG, Ollama for models, Whisper for transcription)
- **services/** - Core productivity applications (Windmill workflows, Logseq notes, NocoDB databases, Vikunja tasks)
- **nas/** - Storage solutions (MinIO object storage, Nextcloud files, Redis caching)
- **hosting/** - Infrastructure tools (Caddy reverse proxy, Portainer management, Uptime-Kuma monitoring)
- **automations/** - Shell scripts and workflow automation tools
- **graveyard/** - Archived/alternative solutions for reference

### Key Architectural Patterns

1. **Docker Compose Structure**: Each service directory contains:
   - `docker-compose.yml` with custom logging and health checks
   - `.env.example` template with placeholder variables
   - Connection to the shared `exist` overlay network
   - Integration with TrueNAS NFS for persistent storage

2. **Configuration System**: Dynamic `EXIST_DEFAULT_*` variables from root `.env` automatically propagate to all service configurations

3. **Network Architecture**: All services communicate through the encrypted `exist` overlay network, automatically created with Docker Compose

### Core Data Flow
1. **Meeting Recording** → Whisper transcription → LibreChat with RAG → Vikunja task creation
2. **File Storage** → MinIO triggers → Windmill workflows → Automated processing
3. **Note-taking** → Logseq knowledge base → LibreChat RAG integration → Contextual AI assistance

## 🔧 Configuration System

### Dynamic Variable System
The project uses `EXIST_DEFAULT_*` variables in the root `.env` for consistent configuration across all services:

```bash
# Root .env variables automatically propagate
EXIST_DEFAULT_EMAIL=your@email.com
EXIST_DEFAULT_USERNAME=yourusername
EXIST_DEFAULT_PASSWORD=generated_password
EXIST_DEFAULT_TRUENAS_SERVER_ADDRESS=192.168.1.100
```

### Placeholder Processing
The unified configuration system handles multiple placeholder types:

- `EXIST_CLI` - Interactive prompts during setup
- `EXIST_24_CHAR_PASSWORD` - Auto-generated secure passwords
- `EXIST_32_CHAR_HEX_KEY` / `EXIST_64_CHAR_HEX_KEY` - Hex keys for APIs
- `EXIST_DEFAULT_*` - Dynamic variable substitution

### Service Enablement
Individual services are controlled via boolean environment variables:
```bash
EXIST_ENABLE_AI_LIBRECHAT=true
EXIST_ENABLE_SERVICES_WINDMILL=true
EXIST_ENABLE_NAS_MINIO=false
```

## 🛠️ Development Workflow

### Initial Project Setup
1. Run `./existential.sh` to process all `.example` files
2. Configure TrueNAS NFS settings for persistent storage
3. Enable desired services in root `.env` file
4. Start containers with `docker compose up -d`
5. Run initial setup scripts with `./automations/existential/run_initial_setup.sh`

### Working with Services
- Each service is self-contained with its own `docker-compose.yml`
- Configuration templates use `.example` files that never get overwritten
- Services communicate using container names as hostnames
- External access configured through Caddy reverse proxy

### Common Development Tasks
- **Add new service**: Create directory structure, docker-compose.yml, .env.example
- **Modify configuration**: Update .example files, regenerate with existential.sh
- **Debug services**: Use `docker logs` and health check endpoints
- **Update services**: Modify docker-compose.yml and restart containers

## 🔗 Inter-Service Dependencies

### Critical Service Dependencies
- **Windmill** requires PostgreSQL database and waits for health checks
- **LibreChat** integrates with Ollama for AI models and MongoDB for storage
- **Vikunja** connects to PostgreSQL for task management
- **Services requiring setup**: Windmill (superadmin creation) and Vikunja (user creation)

### Network Communication
Services communicate within the Docker network using predictable patterns:
- `http://windmill_server:8000` - Windmill API
- `librechat-mongodb:27017` - MongoDB connection
- Container names serve as DNS hostnames within the `exist` network

## 📊 Key Services

### Workflow Automation
- **Windmill** (port 8800): Python/TypeScript/Go/Bash script execution platform
- **RabbitMQ**: Message queue for workflow triggers

### AI Stack
- **LibreChat**: RAG interface for notes and digital context
- **Ollama**: Local AI model hosting and inference
- **Whisper**: Audio transcription service

### Data & Storage
- **NocoDB**: Low-code database platform
- **MinIO**: S3-compatible object storage with webhook triggers
- **Redis**: Caching and session storage

### Productivity Tools
- **Logseq**: Graph-based note-taking
- **Vikunja**: Task management with API integration
- **Dashy**: Service dashboard and access portal

## 🚦 Service Access

After setup, access services through the dashboard at:
- **Dashboard**: `https://local.existential.company/`
- All services use HTTPS with automatically trusted certificates
- Individual service URLs follow pattern: `https://service.local.existential.company/`

## ⚠️ Important Notes

### Storage Requirements
- Requires TrueNAS server for NFS volume mounts
- Configure `EXIST_DEFAULT_TRUENAS_SERVER_ADDRESS` and `EXIST_DEFAULT_TRUENAS_CONTAINER_PATH`
- Services use mix of local volumes and NFS mounts based on persistence needs

### Security Considerations
- No hardcoded passwords - all credentials from environment variables
- Self-signed certificates for local HTTPS access
- VPN recommended for external access over reverse proxy solutions

### File Safety
- Configuration processing never overwrites existing files
- Always creates `.example` counterparts safely
- Use `--force` flag only when explicitly needed to overwrite