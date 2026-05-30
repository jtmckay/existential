---
sidebar_position: 5
---

# LightRAG

- Source: https://github.com/HKUDS/LightRAG
- License: MIT

Local, read-only GraphRAG over an Obsidian vault. LightRAG auto-extracts entities
and relationships from prose markdown — no wikilinks required — and exposes the
result as an MCP tool that [hermes-agent](./hermes) can call when retrieval is warranted.

## Architecture

```
Open WebUI / opencode               (browser path: https://hermes-agent.internal)
       │  (container path: http://hermes-agent:8642 — OpenAI-compatible API)
       ▼
  hermes-agent
       │  (MCP tool call → http://lightrag:9621, X-API-Key auth)
       ▼
  LightRAG server                       ← Docker container on exist network
       │  (entity-extraction LLM + embeddings → http://ollama:11434)
       ▼                                  ▲
  Obsidian vault                          │
   (read-only bind mount)                 │
       │                                  │
       └── rag_storage/                   │
           (writable volume — graph,      │
           vector, KV store)              │
                                          │
  Ollama  ─────────────────────────────────
   (LLM + embedding host)
```

Neither Open WebUI nor opencode talks to LightRAG directly. All vault access is
routed through hermes-agent, which centralizes tool configuration and lets the
agent decide when to query the graph. LightRAG itself talks straight to Ollama
for entity extraction and embeddings — no hermes hop on the ingestion path.

## Port

| Service | Port |
|---|---|
| LightRAG REST + MCP | 9621 |

## Setup

1. Enable the service in `.env.exist`:

   ```env
   EXIST_IS_AI_LIGHTRAG=true
   ```

2. Run `./existential.sh` from the repo root. It renders `ai/lightrag/.env`
   and `ai/lightrag/docker-compose.yml` from the examples, populates
   `LIGHTRAG_API_KEY` from `EXIST_LIGHTRAG_API_KEY`, and regenerates the
   master `docker-compose.yml`.

3. Replace `/path/to/obsidian/vault` in `ai/lightrag/docker-compose.yml` with
   your vault path.

4. Restart `hermes-agent` so it picks up the new `LIGHTRAG_API_KEY`:

   ```bash
   docker compose up -d hermes-agent
   ```

5. Bring up LightRAG:

   ```bash
   docker compose up -d lightrag
   ```

6. The `lightrag` MCP server is already declared in `ai/hermes/data/config.yaml`.
   Reload it from the gateway with `/reload-mcp`, then confirm:

   ```bash
   docker exec hermes-agent /opt/hermes/.venv/bin/hermes mcp list
   ```

7. Trigger initial ingestion (one-time, slow — minutes to hours):

   ```bash
   curl -X POST http://localhost:9621/documents/scan \
     -H "X-API-Key: $(grep ^LIGHTRAG_API_KEY ai/lightrag/.env | cut -d= -f2)"
   ```

## Re-ingestion

A Decree cron job (`automations/cron/lightrag-rescan.md`) runs `lightrag-rescan`
nightly at 03:00. Manual trigger:

```bash
docker exec decree decree run lightrag-rescan
```

## Authentication

`EXIST_LIGHTRAG_API_KEY` in `.env.exist` is the shared secret. LightRAG
requires it on every request as `X-API-Key`. hermes-agent receives the same value
via the `LIGHTRAG_API_KEY` env passthrough and injects it into MCP calls through
the `headers` block in `ai/hermes/data/config.yaml`.

## Models

- **LLM (entity extraction)**: bound straight to Ollama at `http://ollama:11434/v1`
  (Docker service DNS over the `exist` network). Earlier versions routed
  extraction through hermes-agent's gateway so the model would track whatever
  hermes was set to; that added a hop and made hermes's chat-model choice
  silently steer extraction quality. The default model is `gemma3:27b` —
  change `LLM_MODEL` in `ai/lightrag/.env` to pick a different one.
- **Embedding**: `nomic-embed-text:latest` (dim 768) via `http://ollama:11434`.

**Do not change the embedding model after first ingestion.** Switching requires
wiping `rag_storage` and re-ingesting the entire vault.

## Storage

| Path | Purpose | Persistence |
|---|---|---|
| `/inputs` | Obsidian vault | Read-only host bind mount |
| `/app/rag_storage` | Graph, vectors, KV cache | Writable — fully reproducible from the vault |

`rag_storage` is gitignored. Treat it as a derived artifact; if it gets corrupted
or you change the embedding model, delete it and re-ingest.

## Debugging

```bash
docker compose logs lightrag
docker exec hermes-agent /opt/hermes/.venv/bin/hermes mcp list
```

## Why not...

| Alternative | Why not |
|---|---|
| **obra/knowledge-graph** | Great for wikilink graph traversal; lacks prose-based entity extraction |
| **Basic Memory** | Designed as a write-forward AI memory layer, not a query interface over a pre-existing vault |
| **Neural Composer Obsidian plugin** | UI wrapper that manages a LightRAG server lifecycle from Obsidian. Not needed — Docker is the lifecycle manager here, and Obsidian does not need to be running for queries |
| **LightRAG as an Ollama-style model in Open WebUI** | Would route every message to the vault, eliminating hermes-agent's ability to decide when retrieval is warranted |
| **lightrag-mcp (PyPI subprocess)** | Thin HTTP→stdio wrapper; valid fallback. Direct HTTP MCP is simpler since the container is already running |
| **InfraNodus** | Cloud SaaS — all data must remain local |
| **drewburchfield/obsidian-graph** | Requires Postgres/pgvector for marginal gain over LightRAG's built-in NanoVectorDB |
| **`hermes mcp add --auth header`** | CLI hardcodes `Authorization: Bearer`; LightRAG needs `X-API-Key`. Edit `config.yaml` directly |
| **`host.docker.internal` for the LLM or embedding host** | Routes out of Docker and back in via the host port. Both `hermes-agent` and `ollama` are on the `exist` network — use their Docker DNS names |
