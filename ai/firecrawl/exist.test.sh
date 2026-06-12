#!/usr/bin/env bash
# exist.test.sh — validate that firecrawl is fully operational.
#
# See CLAUDE.md "Service test scripts" for the convention.

set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../src/test" && pwd)/exist-test.sh"
exist_self_elevate
exist_test_init "firecrawl" EXIST_IS_AI_FIRECRAWL
skip_if_disabled

env_var_set "FIRECRAWL_API_KEY"

# Root endpoint — unauthenticated, returns {"message":"Firecrawl API",...}
probe_service "firecrawl /" firecrawl 3002 / 200

# Authenticated scrape endpoint — confirms the API key works and the workers
# are up. A POST to /v1/scrape with a bad body returns 400, which still proves
# auth passed (401 would mean the key is wrong).
if [ -n "${FIRECRAWL_API_KEY:-}" ]; then
    http_probe_any "firecrawl /v1/scrape (authed)" \
                   "http://firecrawl:3002/v1/scrape" "^(400|422)$" 5 \
                   -X POST \
                   -H "Authorization: Bearer ${FIRECRAWL_API_KEY}" \
                   -H "Content-Type: application/json" \
                   -d '{}'
fi

# MCP server — streamable HTTP initialize handshake must succeed (this is the
# endpoint hermes connects to).
http_probe_any "firecrawl-mcp /mcp (initialize)" \
               "http://firecrawl-mcp:3003/mcp" "^200$" 10 \
               -X POST \
               -H "Content-Type: application/json" \
               -H "Accept: application/json, text/event-stream" \
               -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"exist-test","version":"0"}}}'

finish
