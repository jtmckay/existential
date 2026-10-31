#!/usr/bin/env bash
# hermes — interactive first-time model setup.
#
# Launches the hermes model picker inside the running container so you can
# select the LLM provider and model. Requires a TTY — run directly, not
# piped or in CI.
#
# Run after 'docker compose up -d':
#   ./existential.sh run hermes setup
set -euo pipefail

if ! docker inspect hermes-agent --format '{{.State.Running}}' 2>/dev/null | grep -q true; then
    echo "hermes-agent is not running. Start it first:"
    echo ""
    echo "  docker compose up -d"
    echo ""
    exit 1
fi

echo "Launching hermes model setup (interactive)..."
echo ""
docker exec -it \
    -u "${EXIST_PUID:-1000}" \
    hermes-agent \
    /opt/hermes/.venv/bin/hermes model

echo ""
echo "Model configured. Restart hermes-agent to apply if needed:"
echo ""
echo "  docker compose restart hermes-agent"
echo ""
