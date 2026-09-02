---
sidebar_position: 9
---

# Firecrawl

- Source: https://github.com/firecrawl/firecrawl
- License: [AGPL-3](https://www.gnu.org/licenses/agpl-3.0.html)
- Alternatives: Crawl4AI, Playwright, Scrapy, Jina Reader

Web scraping and crawling API that turns a URL into clean markdown an AI model can read.
Agents use it to fetch pages without each one carrying its own browser automation.

## Containers

| Container | Role |
|---|---|
| `firecrawl` | REST API and job harness (port 3002) |
| `firecrawl-mcp` | MCP server — streamable HTTP at `http://firecrawl-mcp:3003/mcp` |
| `firecrawl-playwright` | Headless browser microservice (internal) |
| `firecrawl-redis` | Rate limiting and job-state cache |
| `firecrawl-rabbitmq` | Crawl job queue |
| `firecrawl-postgres` | Crawl results and job history |

## Access

- Containers: `http://firecrawl:3002` on the `exist` network — **unauthenticated**
- Browser/LAN: `https://firecrawl.EXIST_DOMAIN`, which requires
  `Authorization: Bearer $FIRECRAWL_API_KEY`
- Agents: point an MCP client at `http://firecrawl-mcp:3003/mcp`

Self-hosted Firecrawl has no authentication of its own: `USE_DB_AUTHENTICATION=true` needs
Supabase, and with it false the server accepts any API key, including none. Caddy carries the
bearer check on `firecrawl.EXIST_DOMAIN` instead, so that is the only path that is gated —
anything already on the `exist` bridge can call the API without a key.

## Enable

```bash
EXIST_IS_AI_FIRECRAWL=true
```

Then `./existential.sh && docker compose up -d` from the repo root.

## Notes

Its Postgres volume is `volumes/firecrawl_postgres_data`, declared `db: true` — local only,
never NFS. Scraped content is a cache: if you lose it, re-crawl.
