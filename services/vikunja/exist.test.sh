#!/usr/bin/env bash
# exist.test.sh — validate that vikunja is operational.
#
# See CLAUDE.md "Service test scripts" for the convention.

set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../src/test" && pwd)/exist-test.sh"
exist_self_elevate
exist_test_init "vikunja" EXIST_IS_SERVICES_VIKUNJA
skip_if_disabled

# vikunja serves the UI + API on :3456. /api/v1/info is unauthenticated.
probe_service "vikunja /api/v1/info" vikunja 3456 /api/v1/info 200
tcp_probe     "vikunja-db:5432"      vikunja-db 5432

finish
