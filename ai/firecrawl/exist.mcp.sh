#!/usr/bin/env bash
# firecrawl — register the Firecrawl MCP server in hermes-agent.
#
# Run once after both services are healthy:
#   ./existential.sh run firecrawl mcp
#
# Re-running is safe; hermes-agent overwrites the existing entry.
set -euo pipefail

if [[ "${IN_CONTAINER:-}" == "1" ]]; then
    echo "[firecrawl] exist.mcp.sh must run on the host (needs docker socket)." >&2
    exit 1
fi

echo "[firecrawl] Registering firecrawl MCP server in hermes-agent..."
docker exec \
    -u "${EXIST_PUID:-1000}" \
    hermes-agent \
    /opt/hermes/.venv/bin/hermes mcp add firecrawl \
        --url http://firecrawl-mcp:3003/mcp

echo "[firecrawl] Done. Hermes will use firecrawl on the next task."
