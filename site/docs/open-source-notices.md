---
sidebar_position: 4
---

# Open Source Notices

This service is built from open-source software. This page provides attribution to those
projects and, where their licenses require it (notably the GNU **AGPL**, **MPL-2.0**, and
**SSPL**), the offer of **Corresponding Source**. It is the canonical notices page to link
from a hosted product's footer, Terms of Service, or "About" screen.

For the commercial-risk view of these same licenses, see the
[Licensing & Host-for-Profit Audit](./licensing).

## How this software is run

- **Unmodified upstream images.** Every component runs from its official upstream container
  image. We do not fork or patch application source.
- **Versions are pinned and public.** The exact image tag of every component is recorded in
  that service's `docker-compose.yml` in the public source repository:
  **https://github.com/jtmckay/existential**
- **Our configuration is public too.** Deployment configuration, templates, and any
  automation live in that same public repository, so the complete source needed to build and
  run this stack is openly available.

## Offer of Corresponding Source (AGPL / MPL / SSPL)

For every component under a network-copyleft license, the **Corresponding Source of the
exact version operated here** is the upstream project listed below, at the image tag pinned
in our public repository. Because these components are run **unmodified**, the upstream
source *is* the Corresponding Source.

If you would like the source on physical media or cannot access the links below, send a
written request and we will provide it: **[insert contact email]**.

### Network-copyleft components (source offered)

| Component | License | Source |
|---|---|---|
| Nextcloud | AGPL-3.0 | https://github.com/nextcloud/server |
| Immich | AGPL-3.0 | https://github.com/immich-app/immich |
| Mealie | AGPL-3.0 | https://github.com/mealie-recipes/mealie |
| NocoDB | AGPL-3.0 | https://github.com/nocodb/nocodb |
| Vikunja | AGPL-3.0 | https://github.com/go-vikunja/vikunja |
| Logseq | AGPL-3.0 | https://github.com/logseq/logseq |
| Lowcoder | AGPL-3.0 | https://github.com/lowcoder-org/lowcoder |
| MinIO | AGPL-3.0 | https://github.com/minio/minio |
| Grafana | AGPL-3.0 | https://github.com/grafana/grafana |
| Loki / Promtail | AGPL-3.0 | https://github.com/grafana/loki |
| Collabora Online (CODE) | MPL-2.0 | https://github.com/CollaboraOnline/online |
| Redis (`redis:alpine`, v8) | AGPLv3 *(option selected)* | https://github.com/redis/redis |
| MongoDB (bundled in Lowcoder) | SSPL-1.0 | https://github.com/mongodb/mongo |
| Proxmox VE (host hypervisor) | AGPL-3.0 | https://git.proxmox.com |

## Permissive components (attribution)

Provided under permissive licenses (MIT, Apache-2.0, BSD, zlib, GPL, PostgreSQL). No source
offer is required; attribution is given here.

| Component | License | Source |
|---|---|---|
| Actual Budget | MIT | https://github.com/actualbudget/actual |
| Appsmith (CE) | Apache-2.0 | https://github.com/appsmithorg/appsmith |
| Dashy | MIT | https://github.com/Lissy93/dashy |
| Home Assistant | Apache-2.0 | https://github.com/home-assistant/core |
| IT-Tools | GPL-3.0 | https://github.com/CorentinTh/it-tools |
| Ntfy | Apache-2.0 / GPL-2.0 | https://github.com/binwiederhier/ntfy |
| Chatterbox TTS | MIT | https://github.com/devnen/Chatterbox-TTS-Server |
| ComfyUI | GPL-3.0 | https://github.com/comfyanonymous/ComfyUI |
| Hermes (agent + workspace) | MIT | https://github.com/NousResearch/hermes-agent |
| LightRAG | MIT | https://github.com/HKUDS/LightRAG |
| Ollama | MIT | https://github.com/ollama/ollama |
| WhisperX (whisperX-FastAPI) | MIT | https://github.com/pavelzbornik/whisperX-FastAPI |
| Open WebUI | BSD-3 + branding clause | https://github.com/open-webui/open-webui |
| Caddy | Apache-2.0 | https://github.com/caddyserver/caddy |
| Docker Engine / Moby | Apache-2.0 | https://github.com/moby/moby |
| Pi-hole | EUPL-1.2 | https://github.com/pi-hole/pi-hole |
| Portainer CE | zlib | https://github.com/portainer/portainer |
| Prometheus | Apache-2.0 | https://github.com/prometheus/prometheus |
| Uptime Kuma | MIT | https://github.com/louislam/uptime-kuma |
| PostgreSQL | PostgreSQL License | https://github.com/postgres/postgres |
| MariaDB | GPL-2.0 | https://github.com/MariaDB/server |
| Valkey | BSD-3 | https://github.com/valkey-io/valkey |
| Coolify (control plane) | Apache-2.0 | https://github.com/coollabsio/coolify |

## Branding & trademarks

- **Open WebUI** branding is retained intact, as required by its license for deployments
  exceeding fifty users.
- **Coolify**, **Nextcloud**, **Immich**, and all other product names and logos are
  trademarks of their respective owners and are used here for identification only. No
  affiliation or endorsement is implied.

## Per-component detail

Each service's own documentation page carries its individual `Source` and `License` line —
see the [AI](./ai/), [Services](./services/), [Storage](./storage/), and
[Hosting](./hosting/) sections.
