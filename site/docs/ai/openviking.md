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
| `openviking-decree` | Backup sidecar plus the knowledgebase indexer cron |

## Access

- Containers: `http://openviking:1933` on the `exist` network
- Browser (Web Studio): `https://openviking.EXIST_DOMAIN`
- Agents: [Hermes](./hermes) connects to it as an MCP server

## Enable

```bash
EXIST_IS_AI_OPENVIKING=true
```

Then `./existential.sh && docker compose up -d` from the repo root.

## What it indexes

`workspace/` at the repo root — the same tree [Hermes](./hermes) mounts at
`/opt/data/workspace` and code-server mounts at `/workspace`. Everything you actually
work on is searchable without a second knowledgebase directory to keep in step.

The `openviking-index-dir` routine uploads it into `viking://resources/workspace` every
15 minutes. It is incremental: unchanged files are skipped, changed files replace their
old copy, and files you delete on disk leave the index on the next run. A first pass over
a large tree takes a while — each file is embedded on the way in.

The directory is mounted on the **sidecar**, not on `openviking`. OpenViking's HTTP and
MCP APIs both refuse host filesystem paths outright, so content only ever reaches it by
upload — which is also why there is no watched-directory setup.

`workspace/ai/` — where the agent automations write — is indexed like everything else, so
an agent can find and build on what an earlier run produced. It is excluded from the
MinIO sync instead, which is what stops that output from triggering more runs. See
[File Processor](../decree/file-change-processing).

## What it stores

| Volume | Tier | Contents |
|---|---|---|
| `openviking_data` | 2 — local, backed up | Vector store and workspace. Embedded DB, never NFS. |
| `openviking_index_cache` | 3 — ephemeral | Upload manifest, so unchanged files are not re-embedded each run |

Only the vector store is backed up. The manifest is a cache: losing it costs one full
re-index, not any content.
