---
sidebar_position: 3
---

# Licensing & Host-for-Profit Audit

Existential is built almost entirely from third-party open-source apps. Running them for
yourself is unambiguously fine. **Hosting them for paying tenants** is a different legal
question — you are now offering someone else's software to third parties over a network,
and *each app's own license governs whether you may do that, not the license of the
platform you deploy with.*

This page audits every app in the stack for commercial multi-tenant hosting. It is the
catalog you build your offering from: host the green ones freely, comply with the yellow
ones, and resolve the red ones before charging for them.

:::note Not legal advice
This is an engineering summary to triage risk, not legal advice. Licenses change — Redis,
Open WebUI, and MinIO all relicensed within the last two years — so confirm each app at its
current version and get counsel before launch. Re-run this audit on every version bump.
:::

## The platform itself is the easy part

[Coolify](https://github.com/coollabsio/coolify/blob/v4.x/LICENSE) (the deployment control
plane) is plain **Apache-2.0** with no custom clauses: commercial use, reselling, and
multi-tenant operation are all permitted, and there is no "offer as a service" copyleft.
The only constraints are (1) **no trademark grant** — you can't brand your product
"Coolify" — and (2) preserve notices if you redistribute it (you don't; it stays on your
control-plane host). The maintainers *ask* (non-binding) that you not resell Coolify as
your own product; using it as infrastructure to host other apps does not conflict with that.

**The real exposure is the hosted catalog below.**

## How to read the flags

| Flag | Meaning | What you must do |
|---|---|---|
| 🟢 **Permissive** | MIT · Apache-2.0 · BSD · zlib · PostgreSQL · MPL-2.0 · **GPL\*** | Nothing. Host freely. |
| 🟡 **Network copyleft** | **AGPL-3.0** · SSPL | You may host, but must offer your users the *running* source, including any modifications you make. Trivial if you run upstream unmodified and link to its source. |
| 🔴 **Explicit restriction** | branding / commercial-hosting clause | Resolve before monetizing — keep mandated branding, or obtain a commercial/enterprise license. |

**\* GPL is not AGPL.** Plain GPL-2.0/3.0 (ComfyUI, IT-Tools, MariaDB) imposes **no**
obligations for hosted/SaaS use — its conditions trigger only when you *distribute the
binary*, which you don't. GPL apps are safe to host. Only **AGPL** (and SSPL) reach
across the network.

## AI

| App | Upstream | License | Flag | Notes / action |
|---|---|---|---|---|
| Chatterbox | [chatterbox-tts](https://github.com/devnen/Chatterbox-TTS-Server) (Resemble AI) | MIT | 🟢 | Model and server both MIT. |
| ComfyUI | [ComfyUI](https://github.com/comfyanonymous/ComfyUI) | GPL-3.0 | 🟢 | GPL has no SaaS clause — safe to host. |
| Hermes | [hermes-agent](https://github.com/NousResearch/hermes-agent) | MIT | 🟢 | Custom existential service. |
| LightRAG | [LightRAG](https://github.com/HKUDS/LightRAG) | MIT | 🟢 | |
| MCP | custom (Node base) | Your code | 🟢 | First-party. |
| Ollama | [ollama](https://github.com/ollama/ollama) | MIT | 🟢 | |
| Open WebUI | [open-webui](https://github.com/open-webui/open-webui) | BSD-3 + **branding clause** | 🔴 | For **>50 users** (rolling 30 days) you must **keep "Open WebUI" branding** or buy an enterprise license. White-label = enterprise license required. Hosting *with* branding intact is allowed. |
| WhisperX | [whisperX-FastAPI](https://github.com/pavelzbornik/whisperX-FastAPI) | MIT | 🟢 | |

## Productivity & services

| App | Upstream | License | Flag | Notes / action |
|---|---|---|---|---|
| Actual Budget | [actual](https://github.com/actualbudget/actual) | MIT | 🟢 | |
| Appsmith | [appsmith](https://github.com/appsmithorg/appsmith) (CE) | Apache-2.0 | 🟢 | |
| Dashy | [dashy](https://github.com/Lissy93/dashy) | MIT | 🟢 | |
| Decree | custom / cloned | Your code | 🟢 | First-party automation. |
| Home Assistant | [core](https://github.com/home-assistant/core) | Apache-2.0 | 🟢 | |
| Immich | [immich](https://github.com/immich-app/immich) | AGPL-3.0 | 🟡 | Run unmodified; link to source. Bundles Valkey (BSD) + Postgres. |
| IT-Tools | [it-tools](https://github.com/CorentinTh/it-tools) | GPL-3.0 | 🟢 | Client-side; GPL, no SaaS clause. |
| Logseq | [logseq](https://github.com/logseq/logseq) | AGPL-3.0 | 🟡 | |
| Lowcoder | [lowcoder](https://github.com/lowcoder-org/lowcoder) (CE) | AGPL-3.0 | 🟡 | Also bundles **MongoDB (SSPL)** internally — see databases. |
| Mealie | [mealie](https://github.com/mealie-recipes/mealie) | AGPL-3.0 | 🟡 | |
| NocoDB | [nocodb](https://github.com/nocodb/nocodb) | AGPL-3.0 | 🟡 | |
| Ntfy | [ntfy](https://github.com/binwiederhier/ntfy) | Apache-2.0 / GPL-2.0 | 🟢 | |
| Vikunja | [vikunja](https://github.com/go-vikunja/vikunja) | AGPL-3.0 | 🟡 | Desktop app is GPL-3.0; server is AGPL. |

## Storage

| App | Upstream | License | Flag | Notes / action |
|---|---|---|---|---|
| Collabora | [collabora online](https://github.com/CollaboraOnline/online) (CODE) | MPL-2.0 | 🟢 | Commercially hostable; CODE is not *recommended* for production (no LTS/support) — that's operational, not legal. Enterprise subscription optional. |
| MinIO | [minio](https://github.com/minio/minio) | AGPL-3.0 | 🟡 | AGPL obligations apply; MinIO Ltd. enforces actively and has been trimming community-edition features — track upstream closely. |
| Nextcloud | [server](https://github.com/nextcloud/server) | AGPL-3.0 | 🟡 | The flagship AGPL app; run unmodified + link source. Bundles MariaDB (GPL). |
| Redis | [redis](https://github.com/redis/redis) (v8) | Tri: RSALv2 / SSPLv1 / **AGPLv3** | 🟢 | Choose **AGPLv3 or RSALv2** — both permit hosting. (Redis 7.4–7.x was RSAL/SSPL-only; v8+ restored the open option.) |

## Infrastructure & control plane

This tier is *your* plumbing, not a product you sell. Obligations only trigger if a tenant
is given network access to that specific instance (e.g. you hand them a Grafana dashboard).

| Component | License | Flag | Notes |
|---|---|---|---|
| Caddy | Apache-2.0 | 🟢 | |
| Cloudflare | external SaaS | N/A | Governed by Cloudflare's ToS, not a redistributable. |
| Docker Engine / Moby | Apache-2.0 | 🟢 | |
| Grafana | AGPL-3.0 | 🟡 | Only if tenants get dashboard access. |
| Loki / Promtail | AGPL-3.0 | 🟡 | As above. |
| Pi-hole | EUPL-1.2 | 🟢 | Infrastructure. |
| Portainer CE | zlib | 🟢 | |
| Prometheus | Apache-2.0 | 🟢 | |
| Uptime Kuma | MIT | 🟢 | |
| Coolify | Apache-2.0 | 🟢 | Don't use the Coolify name/branding for your product. |

## Supporting databases

Bundled *inside* app stacks, not offered as standalone database services.

| Engine | License | Flag | Notes |
|---|---|---|---|
| PostgreSQL | PostgreSQL License | 🟢 | Permissive. |
| MariaDB | GPL-2.0 | 🟢 | GPL — hosting imposes no obligations. |
| MongoDB (via Lowcoder) | SSPL-1.0 | 🟡 | SSPL targets *offering the database as a service*. Here it's an internal component of Lowcoder, so the trigger is likely not hit — but don't expose it as a standalone DB product. |
| Valkey (via Immich) | BSD-3 | 🟢 | The open Redis fork. |

## Compliance checklist

- [ ] Every hosted app's license recorded (this page) and re-checked at its current version.
- [ ] **AGPL apps run unmodified**, *or* your modifications are published and linked in-app.
- [ ] The [Open Source Notices](./open-source-notices) page is exposed to tenants, linking each AGPL app's running source.
- [ ] **Open WebUI**: branding kept intact, *or* an enterprise license obtained for white-label.
- [ ] **MongoDB/Redis** not exposed as standalone database services; Redis license option chosen (AGPLv3/RSALv2).
- [ ] No **Coolify** trademark in your product's name or branding.
- [ ] Audit re-run on every app version bump — licenses change without notice.

## Bottom line

Most of the catalog is 🟢 and hostable without ceremony. The 🟡 AGPL apps (Nextcloud,
Immich, Mealie, NocoDB, Vikunja, Logseq, Lowcoder, MinIO, Grafana/Loki) are compliant as
long as you run them unmodified and offer your tenants the source — the
[Open Source Notices](./open-source-notices) page covers it. The only genuine 🔴 is
**Open WebUI's branding clause**: keep their branding or buy an enterprise license. Resolve
that one and the catalog is clear for commercial hosting.
