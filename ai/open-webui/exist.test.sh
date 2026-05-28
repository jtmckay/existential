#!/usr/bin/env bash
# exist.test.sh — validate that open-webui is fully operational.
#
# See CLAUDE.md "Service test scripts" for the convention.

set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../src/test" && pwd)/exist-test.sh"
exist_self_elevate
exist_test_init "open-webui" EXIST_IS_AI_OPEN_WEBUI
skip_if_disabled

# open-webui listens on :8080. /health is unauthenticated.
probe_service     "open-webui /health" open-webui 8080 /health 200
probe_service_any "open-webui UI"      open-webui 8080 /       "^(200|302|307)$"

finish
