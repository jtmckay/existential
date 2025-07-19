# existential

Elevating static personal knowledge management, into an active personal operating system.

![Architecture Diagram](architecture.png)

## [Hosting](/hosting/README.md)

## Getting started
#### Prerequisites
##### Docker
https://www.docker.com/

##### Compatible S3 API
See [/hosting/README.md](/hosting/README.md)

#### Setup
- Copy .env.example files and fill in your values `cp .env.example .env`
- Setup the docker network
- `docker network create exist --subnet=172.18.0.0/24`

#### Run
- ``
- ``

## Applications
### Monitoring/managing containers
- [Portainer](./hosting/portainer/README.md)
- [Uptime-Kuma](./hosting/uptimeKuma/README.md)  (alt: Prometheus & Grafana or https://uptimerobot.com/ or https://www.statuscake.com/)

### File editing [alts](./graveyard/fileEditor.md)
- [Collabora](./nas/collabora/README.md) web app embedded into nextcloud interface (comparable: Office 365/Google Docs)
- [OnlyOffice](https://www.onlyoffice.com/download-desktop.aspx#desktop) desktop app

### Note taking [alts](./graveyard/notes.md)
- [AnyType](https://anytype.io/)

### When: notification/task management [alts](./graveyard/when.md)
- ntfy TBD

### Low code database/spreadsheets [alts](./graveyard/lowcodeDB.md)
- [NocoDB](./services/nocoDB/README.md)

### Low code UI website editor [alts](./graveyard/lowcodeUI.md)
- [Lowcoder](./services/lowcoder/README.md)

### Random tools [alts](./graveyard/tools.md)
- [IT-Tools](./services/itTools/README.md)

### Workflow [alts](./graveyard/lowcodeWorkflow.md)
- Kestra

### Personal finance
- Firefly-III https://github.com/firefly-iii/firefly-iii (TODO: test)

### Coming soon
[AI](./graveyard/ai.md)
