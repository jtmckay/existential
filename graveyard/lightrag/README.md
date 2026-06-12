# LightRAG

Local GraphRAG over an Obsidian vault, exposed as an MCP tool to hermes-agent.

See [site/docs/ai/lightrag.md](../../site/docs/ai/lightrag.md) for the full setup
guide and architectural notes.

## Quick start

1. Set `EXIST_IS_AI_LIGHTRAG=true` in `../../.env.shared`
2. Run `../../existential.sh` from the repo root
3. Edit the vault host path in `docker-compose.yml`
4. `docker compose up -d lightrag`
5. Add the MCP block to `../hermes/data/config.yaml` (see docs)
6. Trigger initial ingestion:

   ```bash
   curl -X POST http://localhost:9621/documents/scan \
     -H "X-API-Key: $LIGHTRAG_API_KEY"
   ```
