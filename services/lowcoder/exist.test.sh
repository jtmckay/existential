#!/usr/bin/env bash
# exist.test.sh — validate that the lowcoder stack is operational.
#
# Covers lowcoder-frontend (user entry), lowcoder-api-service, lowcoder-node-service.
# Mongo + redis are upstream deps — TCP probes only, no inspection.
#
# See CLAUDE.md "Service test scripts" for the convention.

set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../src/lib" && pwd)/exist-test.sh"
exist_self_elevate
exist_test_init "lowcoder" EXIST_IS_SERVICES_LOWCODER
skip_if_disabled

# Caddy routes lowcoder.internal -> lowcoder-frontend:3000.
http_probe_any "lowcoder-frontend UI (direct)" \
               "http://lowcoder-frontend:3000/" "^(200|301|302|307)$"
probe_caddy_any "lowcoder-frontend UI" lowcoder / "^(200|301|302|307)$"

http_probe_any "lowcoder-api-service" "http://lowcoder-api-service:8080/" "^(200|301|302|401|404)$"
tcp_probe       "lowcoder-mongodb:27017" lowcoder-mongodb 27017
tcp_probe       "lowcoder-redis:6379"    lowcoder-redis    6379

finish
