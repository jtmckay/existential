#!/usr/bin/env bash
# exist.test.sh — validate that mealie is operational.
#
# See CLAUDE.md "Service test scripts" for the convention.

set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../src/test" && pwd)/exist-test.sh"
exist_self_elevate
exist_test_init "mealie" EXIST_IS_SERVICES_MEALIE
skip_if_disabled

# mealie serves the UI + API on :9000. /api/app/about is unauthenticated.
probe_service "mealie /api/app/about" mealie 9000 /api/app/about 200
tcp_probe     "mealie-postgres:5432"  mealie-postgres 5432

finish
