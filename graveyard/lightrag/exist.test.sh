#!/usr/bin/env bash
# exist.test.sh — validate that lightrag is fully operational.
#
# See CLAUDE.md "Service test scripts" for the convention.

set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../src/test" && pwd)/exist-test.sh"
exist_self_elevate
exist_test_init "lightrag" EXIST_IS_AI_LIGHTRAG
skip_if_disabled

env_var_set "EXIST_LIGHTRAG_API_KEY"

# LightRAG exposes its API on :9621. /health is unauthenticated.
probe_service "lightrag /health" lightrag 9621 /health 200

# Authenticated endpoint — confirms the API key actually works. Direct only;
# caddy paths would need the header threaded through, which probe_service
# doesn't expose. The /health probes above already exercise routing.
if [ -n "${EXIST_LIGHTRAG_API_KEY:-}" ]; then
    http_probe "lightrag /api/graphs (authed)" \
               "http://lightrag:9621/api/graphs" 200 5 \
               -H "X-API-Key: ${EXIST_LIGHTRAG_API_KEY}"
fi

finish
