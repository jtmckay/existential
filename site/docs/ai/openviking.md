---
sidebar_position: 11
---

# OpenViking

- Source: https://github.com/volcengine/OpenViking
- License: [AGPL-3](https://www.gnu.org/licenses/agpl-3.0.html)
- Alternatives: LightRAG, Chroma, Qdrant, Weaviate

Context database for AI agents. It exposes a `viking://` filesystem holding memory,
resources, and skills, so an agent has somewhere durable to keep what it knows — the
successor to the LightRAG approach of indexing a notes vault.

## Containers

| Container | Role |
|---|---|
| `openviking` | REST API, MCP server, and Web Studio (port 1933) |
| `openviking-decree` | Backup sidecar plus the notes-sync cron |

## Access

- Containers: `http://openviking:1933` on the `exist` network
- Browser (Web Studio): `https://openviking.EXIST_DOMAIN`
- Agents: [Hermes](./hermes) connects to it as an MCP server

## Enable

```bash
EXIST_IS_AI_OPENVIKING=true
```

Then `./existential.sh && docker compose up -d` from the repo root.

## What it stores

| Volume | Tier | Contents |
|---|---|---|
| `openviking_data` | 2 — local, backed up | Vector store and workspace. Embedded DB, never NFS. |
| `notes/` | 3 — ephemeral | Notes synced from an rclone remote; re-syncable |
| `resources/` | 3 — ephemeral | Content scraped via Hermes and [Firecrawl](./firecrawl) |

Only the vector store is backed up. Notes and scraped resources are rebuilt from their
sources, so they're deliberately not in the backup path.
