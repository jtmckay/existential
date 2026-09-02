#!/usr/bin/env bash
# exist.test.sh — validate that firecrawl is fully operational.
#
# See .claude/reference/testing.md for the convention.

set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../src/test" && pwd)/exist-test.sh"
exist_self_elevate
exist_test_init "firecrawl" EXIST_IS_AI_FIRECRAWL
skip_if_disabled

env_var_set "FIRECRAWL_API_KEY"
env_var_set "FIRECRAWL_BULL_AUTH_KEY"

# Postgres credentials must still match the role baked into the data volume at
# initdb time — the failure this catches presents only as "dependency failed to
# start: container firecrawl is unhealthy" on firecrawl-mcp. Checked before the
# HTTP probes so the cause prints above the symptoms it produces.
pg_auth_probe "firecrawl-postgres auth" firecrawl-postgres 5432 \
              "${FIRECRAWL_POSTGRES_USER:-}" "${FIRECRAWL_POSTGRES_PASSWORD:-}" firecrawl

# Root endpoint over the bridge — returns {"message":"Firecrawl API",...}.
# NOT probe_service: the caddy leg is deliberately gated (below), so it does not
# answer 200 and the two legs need different expectations.
http_probe "firecrawl / via firecrawl:3002" "http://firecrawl:3002/" 200 5

# The scraping engine itself — firecrawl delegates every JS-heavy page here, and
# nothing else notices when it dies.
http_probe "firecrawl-playwright /health" "http://firecrawl-playwright:3000/health" 200 5

# Queue backend. nuq-metrics reads job counts straight out of nuq-postgres, so a
# 200 here is the one cheap check that proves the workers' datastore is wired —
# a scrape request alone would only prove the HTTP layer. redis-health is the
# same idea for the rate-limit/state cache.
if [ -n "${FIRECRAWL_BULL_AUTH_KEY:-}" ]; then
    http_probe "firecrawl redis-health" \
               "http://firecrawl:3002/admin/${FIRECRAWL_BULL_AUTH_KEY}/redis-health" 200 5
    http_probe "firecrawl nuq queue metrics" \
               "http://firecrawl:3002/admin/${FIRECRAWL_BULL_AUTH_KEY}/nuq-metrics" 200 5
fi

# /v1/scrape reachable. This proves routing only — self-hosted firecrawl accepts
# ANY bearer (USE_DB_AUTHENTICATION false short-circuits controllers/auth.js), so
# a 400 here says nothing about the key. The key is checked at caddy, below.
http_probe_any "firecrawl /v1/scrape reachable" \
               "http://firecrawl:3002/v1/scrape" "^(400|422)$" 5 \
               -X POST -H "Content-Type: application/json" -d '{}'

# The auth gate. Because firecrawl has no auth of its own, caddy's bearer check
# on firecrawl.<domain> is the entire boundary between the LAN and an open
# scraping proxy — so both halves are asserted: no key must 401, the right key
# must reach the API.
probe_caddy "firecrawl gate rejects no bearer" firecrawl / 401
if [ "${EXIST_IS_HOSTING_CADDY:-false}" = "true" ] && [ -n "${FIRECRAWL_API_KEY:-}" ]; then
    _fc_host="firecrawl.${EXIST_DOMAIN:-x.internal}"
    http_probe "firecrawl gate accepts the bearer" "https://${_fc_host}/" 200 5 \
               -k --connect-to "${_fc_host}:443:caddy:443" \
               -H "Authorization: Bearer ${FIRECRAWL_API_KEY}"
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
