#!/usr/bin/env bash
# openviking — register OpenViking as an MCP server in hermes-agent.
#
# Run once after both services are healthy:
#   ./existential.sh run openviking mcp
#
# Re-running is safe; hermes-agent overwrites the existing entry.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ "${IN_CONTAINER:-}" == "1" ]]; then
    echo "[openviking] exist.mcp.sh must run on the host (needs docker socket)." >&2
    exit 1
fi

echo "[openviking] You will need your OPENVIKING_API_KEY to continue."
echo "             Find it in ai/openviking/.env (OPENVIKING_API_KEY=...)."
echo ""
read -rsp "  Bearer token: " OPENVIKING_API_KEY
echo ""

echo "[openviking] Registering openviking MCP server in hermes-agent..."
docker exec \
    -u "${EXIST_PUID:-1000}" \
    hermes-agent \
    /opt/hermes/.venv/bin/hermes mcp add openviking \
        --url http://openviking:1933/mcp \
        --header "Authorization: Bearer ${OPENVIKING_API_KEY}"

echo "[openviking] Done. Hermes will use openviking on the next task."
