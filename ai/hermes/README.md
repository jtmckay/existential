```
docker compose exec -u "${EXIST_PUID:-1000}" hermes-agent /opt/hermes/.venv/bin/hermes model



docker compose exec -u "${EXIST_PUID:-1000}" hermes-agent /opt/hermes/.venv/bin/hermes mcp add playwright --url http://mcp-playwright:8931/mcp

docker compose exec -u "${EXIST_PUID:-1000}" hermes-agent /opt/hermes/.venv/bin/hermes mcp add firecrawl --url http://firecrawl-mcp:3003/mcp

```
