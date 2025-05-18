# existential

Personal knowledge management, and automations.

![Architecture Diagram](architecture.png)

# Journey to PKM and automation

## Data
### System OS (self hosting)
- [Proxmox](./Proxmox/README.md) (alt: Unraid)

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
- [WPS Office](https://www.wps.com/) (Better powerpoint at least) (alt: LibreOffice/Open Office)

### Note taking
- [Obsidian](./Obsidian/README.md) (managed alt: OneNote/Evernote/Notion)

### Task management
- [Tasks: Super Productivity](./Tasks/README.md) (managed alt: todoist, Notion)

### Low code database (advanced spreadsheets)
- [NocoDB](./NocoDB/README.md) (alt: AirTable)

### Low code UI website editor
- [Appsmith](./Appsmith/README.md) (alt: Retool)

### Random tools
- [IT-Tools](./IT-Tools/README.md) (managed alt: https://it-tools.tech/ or a handful of websites)
- [Fabric](./Fabric/README.md)

### Workflow
- [ActivePieces](./ActivePieces/README.md)
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
