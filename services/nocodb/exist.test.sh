#!/usr/bin/env bash
# exist.test.sh — validate that nocodb is operational.
#
# See CLAUDE.md "Service test scripts" for the convention.

set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../src/test" && pwd)/exist-test.sh"
exist_self_elevate
exist_test_init "nocodb" EXIST_IS_SERVICES_NOCODB
skip_if_disabled

# nocodb serves the UI on :8080.
probe_service_any "nocodb UI"     nocodb 8080 /              "^(200|301|302|307)$"
probe_service     "nocodb health" nocodb 8080 /api/v1/health 200
tcp_probe         "nocodb-postgres:5432" nocodb-postgres 5432

finish
