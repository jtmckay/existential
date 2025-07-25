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
- `docker-compose up -d` in each service directory you want to run.
OR
- Coming soon `./deployStack.sh` to deploy each service marked in main .env

## Applications
### Monitoring/managing containers
- [Dashy](./services/dashy/README.md)
- [Portainer](./hosting/portainer/README.md)
- [Uptime-Kuma](./hosting/uptimeKuma/README.md)

### File editing [alts](./graveyard/fileEditor.md)
- [OnlyOffice](https://www.onlyoffice.com/download-desktop.aspx#desktop)

### Note taking [alts](./graveyard/notes.md)
- [AnyType](https://anytype.io/)
- TODO custom tldraw https://tldraw.dev/ with yjs https://github.com/ueberdosis/hocuspocus

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
