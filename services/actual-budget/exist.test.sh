#!/usr/bin/env bash
# exist.test.sh — validate that actual-budget is operational.
#
# See CLAUDE.md "Service test scripts" for the convention.

set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../src/test" && pwd)/exist-test.sh"
exist_self_elevate
exist_test_init "actual-budget" EXIST_IS_SERVICES_ACTUAL_BUDGET
skip_if_disabled

# Actual server listens on :5006. Root redirects to /app; accept either.
probe_service_any "actual-budget UI" actual-budget 5006 / "^(200|301|302|307)$"

finish
