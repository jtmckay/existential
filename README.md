# Existential
Personal knowledge mangement meets AI automation. Existential is a currated homelab with AI tools, workflow automation, note-taking, file management, and various productivity applications. Ensuring use of only free open source software that can be used commercially (in case a project takes off). Combining all of the best existing solutions into an app who's single purpose is to serve the individual.

### Dashboard (courtesy of [dashy](https://opensource.org/license/mit))
![Dashy](./services/dashy/dashy.png)

## Examples
### Meeting
![Flow diagram](./automations/flows/basic-flow.png)
###### [More detailed diagram](./automations/flows/transcribe/transcription.png)
- Record a meeting (phone or desktop)
- Get notified with the transciption and summary
- Add tasks in Vikunja
##### ![Vikunja](services/vikunja/vikunja.png)

### Recall
![LibreChat UI](./ai/libreChat/recall.png)
- Chat with your notes using [LibreChat](./ai/libreChat/README.md)

## Applications
### AI
- [LibreChat](./ai/libreChat/README.md) (interface with RAG: all notes/digital context)
- [Ollama](./ai/ollama/README.md) (general AI)
- [Whisper](./ai//whisper/README.md) (transcription)

### Workflow automation [alts](./graveyard/lowcodeWorkflow.md)
- [Windmill](./services/windmill/README.md)

### Note taking [alts](./graveyard/notes.md)
- [Logseq](./services/logseq/README.md)

### Recipe management
- [Mealie](./services/mealie/README.md)

### Personal finance
- Firefly-III https://github.com/firefly-iii/firefly-iii (TBD)

### File editing [alts](./graveyard/fileEditor.md)
- [OnlyOffice](https://www.onlyoffice.com/download-desktop.aspx#desktop)

### When (notification/task management) [alts](./graveyard/when.md)
- [ntfy](./services/ntfy/README.md)
- [Vikunja](./services/vikunja/README.md)

### Low code database/spreadsheets [alts](./graveyard/lowcodeDB.md)
- [NocoDB](./services/nocoDB/README.md)

### Low code UI website editor [alts](./graveyard/lowcodeUI.md)
- [Appsmith](./services/appsmith/README.md) for "internal" apps (more functional)
- [Lowcoder](./services/lowcoder/README.md) for "external" apps (prettier)

### Monitoring/managing containers
- [Dashy](./services/dashy/README.md) dashboard.
- [Portainer](./hosting/portainer/README.md) remote docker container management.
- [Uptime-Kuma](./hosting/uptimeKuma/README.md) notifications when servers go down.

### Random tools [alts](./graveyard/tools.md)
- [IT-Tools](./services/itTools/README.md)

## Architecture diagram
![Architecture Diagram](architecture.png)

## Getting started
### Hosting
Self [hosting](/hosting/README.md).

#### Prerequisites
##### Docker
https://www.docker.com/

##### An S3 compatible API like MinIO for file triggers
See [/hosting/README.md](/hosting/README.md)

#### Setup
- Copy .example files and fill in your values eg: `cp .env.example .env`
- Setup the docker network
- `docker network create exist --subnet=172.18.0.0/24`

#### Run
- `docker-compose up -d` in each service directory you want to run.
OR
- Coming soon `./deployStack.sh` to deploy each service marked in main .env

## Third-Party Software

This project includes multiple open source projects with respective licensing.
