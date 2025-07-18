# existential

Personal knowledge management, and automations.

![Architecture Diagram](architecture.png)

# Journey to PKM and automation

Pick and choose the components to use. EG: use GoogleDrive for files, and skip TrueNAS, MinIO, Redis, and Nextcloud.

## Hosting
### System OS
- [Proxmox](./Proxmox/README.md) (alt: Unraid)

### Container management
- [Docker](./Docker/README.md) (+Swarm alt: Kubernetes)
- [Portainer](./Portainer/README.md) (alt: Dokku, Coolify)

### File redundancy
- [TrueNAS](./TrueNAS/README.md)

### File API
- [MinIO](./MinIO/README.md) (alt: AWS S3)

### Cache
- [Redis](./Redis/README.md)

### File sharing
- [Nextcloud](./Nextcloud/README.md) (managed alt: Dropbox/Onedrive/Google Drive)

## Network
### External network (access self hosted from the internet)
- [Caddy](./Caddy/README.md) (Reverse proxy. Alt: Traefik/Nginx)
- [Cloudflare](./Cloudflare/README.md) (alt: any domain manager/DNS/[Ngrok](./Ngrok/README.md))

### Monitoring
- [Uptime-Kuma](./Uptime-Kuma/README.md)  (alt: Prometheus & Grafana or https://uptimerobot.com/ or https://www.statuscake.com/)

### PubSub (alt: RabbitMQ/Kafka)
- Kafka https://github.com/apache/kafka
- [NSQ](./NSQ/README.md) (UNUSED)
- [RabbitMQ](./RabbitMQ/README.md)

## Applications
### File editing
- [Collabora](./Collabora/README.md) (Powerpoint option is terrible, but web based) (alt: Office 365/Google Docs)
- [OnlyOffice](https://www.onlyoffice.com/download-desktop.aspx#desktop) (TODO: test; I didn't want to have to login to WPS)
- [WPS Office](https://www.wps.com/) (Better powerpoint at least) (alt: LibreOffice/Open Office/OnlyOffice)

### Note taking
- [AnyType](https://anytype.io/) (live P2P local file sync; perfect for VPN)
- [Obsidian](./Obsidian/README.md) (managed alt: OneNote/Evernote/Notion)

### Task management
- ntfy https://github.com/binwiederhier/ntfy (TODO: test)
- [Tasks: Super Productivity](./Tasks/README.md) (managed alt: todoist, Notion)

### Personal finance
- Firefly-III https://github.com/firefly-iii/firefly-iii (TODO: test)

### Low code database (advanced spreadsheets)
- [NocoDB](./NocoDB/README.md) (alt: AirTable)

### Low code UI website editor
- [Lowcoder](./Lowcoder/README.md) (TODO: test)
- [Appsmith](./Appsmith/README.md) (alt: Retool)

### Random tools
- [IT-Tools](./IT-Tools/README.md) (managed alt: https://it-tools.tech/ or a handful of websites)
- [Fabric](./Fabric/README.md)
- [Stirling-PDF](https://github.com/Stirling-Tools/Stirling-PDF) (TODO: test)

### Workflow
- [ActivePieces](./ActivePieces/README.md)
- Kestra https://github.com/kestra-io/kestra (TODO: test)
- [N8N](./N8N/README.md) (Self host only)
- Node-red https://github.com/node-red/node-red

## AI
- [Parakeet](./Parakeet/README.md) (alt: Whisper)
- [Whisper](./Whisper/README.md) (alt: OpenAI)
- [Ollama](./Ollama/README.md) (alt: OpenAI)
- [Speaches](./Speaches/README.md)
- [OpenWebUI](./OpenWebUI/README.md) (alt: ChatGPT)

### Agents
- [Flowise](./Flowise/README.md)
- Huginn https://github.com/huginn/huginn
- Browser use https://github.com/browser-use/browser-use

### Background jobs
- Trigger.dev https://github.com/triggerdotdev/trigger.dev

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
