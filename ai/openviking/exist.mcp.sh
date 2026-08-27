#!/usr/bin/env bash
# openviking — register OpenViking as an MCP server in hermes-agent.
#
# You normally do NOT need this: ai/hermes/exist.initial.sh seeds the same entry
# into hermes' config.yaml before the container first starts. Reach for this to
# RE-register after changing the API key, or to repair a config you edited.
#
#   ./existential.sh run openviking mcp
#
# Re-running is safe; hermes-agent overwrites the existing entry.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ "${IN_CONTAINER:-}" == "1" ]]; then
    echo "[openviking] exist.mcp.sh must run on the host (needs docker socket)." >&2
    exit 1
fi

# The key is already on disk — read it rather than making the user paste it.
OPENVIKING_API_KEY=$(grep -m1 "^OPENVIKING_API_KEY=" "${SCRIPT_DIR}/.env" 2>/dev/null | cut -d= -f2-)

if [[ -z "${OPENVIKING_API_KEY}" ]]; then
    echo "[openviking] OPENVIKING_API_KEY not found in ai/openviking/.env." >&2
    echo "             Run ./existential.sh to render it, or paste it below." >&2
    echo ""
    read -rsp "  Bearer token: " OPENVIKING_API_KEY
    echo ""
fi

if [[ -z "${OPENVIKING_API_KEY}" ]]; then
    echo "[openviking] No API key — aborting." >&2
    exit 1
fi

echo "[openviking] Registering openviking MCP server in hermes-agent..."
docker exec \
    -u "${EXIST_PUID:-1000}" \
    hermes-agent \
    /opt/hermes/.venv/bin/hermes mcp add openviking \
        --url http://openviking:1933/mcp \
        --header "Authorization: Bearer ${OPENVIKING_API_KEY}"

echo "[openviking] Done. Hermes will use openviking on the next task."
