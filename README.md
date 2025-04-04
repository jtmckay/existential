# existential
Personal knowledge management, and automations.

![Architecture Diagram](architecture.jpg)

# Journey to PKM and automation
### File system (self hosting)
- [Proxmox](./Proxmox/README.md) (alt: Unraid)
- [TrueNAS](./TrueNAS/README.md)

### File system API (alt: AWS S3)
- [MinIO](./MinIO/README.md)

### File sharing (managed alt: Dropbox/Onedrive/Google Drive)
- [Redis](./Redis/README.md) (cache for Nextcloud)
- [Nextcloud](./Nextcloud/README.md)

### External network (access self hosted from the internet)
- [Caddy](./Caddy/README.md) (Reverse proxy. Alt: Traefik/Nginx)
- [Cloudflare](./Cloudflare/README.md) (alt: any domain manager/DNS/[Ngrok](./Ngrok/README.md))

### File editing (alt: LibreOffice/Open Office/Office 365/Google Docs)
- [Collabora](./Collabora/README.md)

### Note taking (managed alt: OneNote/Evernote/Notion)
- [Obsidian](./Obsidian/README.md)

### Random tools
- [Tasks: Super Productivity](./Tasks/README.md) (managed alt: todoist)
- [IT-Tools](./IT-Tools/README.md) (managed alt: https://it-tools.tech/ or a handful of websites)
- [Uptime-Kuma](./Uptime-Kuma/README.md)  (alt: Prometheus & Grafana or https://uptimerobot.com/ or https://www.statuscake.com/)
- [NocoDB](./NocoDB/README.md) (alt: AirTable)
- [Appsmith](./Appsmith/README.md) (alt: Retool)
- [Fabric](./Fabric/README.md)

### PubSub (alt: RabbitMQ/Kafka)
- [NSQ](./NSQ/README.md)

## AI
- [Ollama](./Ollama/README.md) (alt: OpenAI)
- [Whisper](./Whisper/README.md) (alt: OpenAI)
- [Speaches](./Speaches/README.md)
- [OpenWebUI](./OpenWebUI/README.md) (alt: ChatGPT)

### Automation workflow options
- [Flowise](./Flowise/README.md)
- [N8N](./N8N/README.md)

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
