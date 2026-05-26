#!/usr/bin/env bash
# exist.test.sh — validate that loki + loki-promtail are operational.
#
# See CLAUDE.md "Service test scripts" for the convention.

set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../src/lib" && pwd)/exist-test.sh"
exist_self_elevate
exist_test_init "loki" EXIST_IS_HOSTING_LOKI
skip_if_disabled

# loki default HTTP listener is :3100. /ready is the standard health endpoint.
http_probe "loki:3100 /ready"      "http://loki:3100/ready"      200

# promtail metrics endpoint on :9080. /ready confirms it has shipped recently.
http_probe "loki-promtail:9080 /ready" "http://loki-promtail:9080/ready" 200

finish
