#!/usr/bin/env bash
# exist.test.sh — validate that uptime-kuma is operational.
#
# See CLAUDE.md "Service test scripts" for the convention.

set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../src/test" && pwd)/exist-test.sh"
exist_self_elevate
exist_test_init "uptime-kuma" EXIST_IS_HOSTING_UPTIME_KUMA
skip_if_disabled

# uptime-kuma serves the UI on :3001.
probe_service_any "uptime-kuma UI" uptime-kuma 3001 / "^(200|301|302|307)$"

finish
