# existential
Personal knowledge management, and automations.

![Architecture Diagram](architecture.jpg)

## Journey to PKM and automation
### Files
- [Proxmox](./Proxmox/README.md)
- [TrueNAS](./TrueNAS/README.md)
- [NSQ](./NSQ/README.md)
- [MinIO](./MinIO/README.md)

### External hosting
- [Caddy](./Caddy/README.md)

### File sharing
- [Redis](./Redis/README.md)
- [Nextcloud](./Nextcloud/README.md)

### Knowledge interfaces
- [Collabora](./Collabora/README.md)
- [Obsidian](./Obsidian/README.md)
- [Tasks](./Tasks/README.md)

### AI
- [Ollama](./Ollama/README.md)
- [Whisper](./Whisper/README.md)
- [Speaches](./Speaches/README.md)
- [OpenWebUI](./OpenWebUI/README.md)

### Databases
- [Postgres](./Postgres/README.md)
- [Qdrant](./Qdrant/README.md)

### Automation workflows
- [Flowise](./Flowise/README.md)
- [N8N](./N8N/README.md)
- [NocoDB](./NocoDB/README.md)

### Unused options
#### External hosting option
- [Ngrok](./Ngrok/README.md)

## Using
### Prerequisites
#### Docker
https://www.docker.com/

### Setup
- Copy .env.example files and fill in your values `cp .env.example .env`
- Setup the docker network
- `docker network create exist --subnet=172.18.0.0/24`

#### Recommended server administrator method
Remote SSH using VSCode.
- Using Remote Explorer VSCode plugin
- Add new connection
- Enter the address of the server
- Save the configuration to user config (or whatever)
- Enter password
- Open directory: wherever you want to clone this repo

### Running
Run a service:
- In the directory for the service you would like to run
- Run the command `docker-compose up -d`

Services are separated in different docker-compose.yml files to make it easier to split up the workload across servers.
