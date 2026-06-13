```
docker compose exec -u "${EXIST_PUID:-1000}" hermes-agent /opt/hermes/.venv/bin/hermes model

# MCP server registration — use the action scripts (preferred):
#   ./existential.sh run mcp mcp
#   ./existential.sh run firecrawl mcp
#   ./existential.sh run openviking mcp
#
# Or run the raw commands:
docker compose exec -u "${EXIST_PUID:-1000}" hermes-agent /opt/hermes/.venv/bin/hermes mcp add playwright --url http://mcp-playwright:8931/mcp
docker compose exec -u "${EXIST_PUID:-1000}" hermes-agent /opt/hermes/.venv/bin/hermes mcp add firecrawl --url http://firecrawl-mcp:3003/mcp
docker compose exec -u "${EXIST_PUID:-1000}" hermes-agent /opt/hermes/.venv/bin/hermes mcp add openviking --url http://openviking:1933/mcp --header "Authorization: Bearer ${OPENVIKING_API_KEY}"

```
