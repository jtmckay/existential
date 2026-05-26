#!/usr/bin/env bash
# exist.test.sh — validate that mcp-playwright is fully operational.
#
# See CLAUDE.md "Service test scripts" for the convention.

set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../src/lib" && pwd)/exist-test.sh"
exist_self_elevate
exist_test_init "mcp" EXIST_IS_AI_MCP
skip_if_disabled

# Playwright MCP server speaks HTTP on :8931. Root may not be a useful endpoint;
# accept anything that proves the container is listening.
probe_service_any "mcp-playwright listening" mcp-playwright 8931 / "^(200|404|405|400)$"

finish
