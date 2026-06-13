#!/usr/bin/env bash
# mcp — register the Playwright MCP server in hermes-agent.
#
# Run once after both services are healthy:
#   ./existential.sh run mcp mcp
#
# Re-running is safe; hermes-agent overwrites the existing entry.
set -euo pipefail

if [[ "${IN_CONTAINER:-}" == "1" ]]; then
    echo "[mcp] exist.mcp.sh must run on the host (needs docker socket)." >&2
    exit 1
fi

echo "[mcp] Registering mcp-playwright MCP server in hermes-agent..."
docker exec \
    -u "${EXIST_PUID:-1000}" \
    hermes-agent \
    /opt/hermes/.venv/bin/hermes mcp add playwright \
        --url http://mcp-playwright:8931/mcp

echo "[mcp] Done. Hermes will use playwright on the next task."
