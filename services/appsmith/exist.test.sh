#!/usr/bin/env bash
# exist.test.sh — validate that appsmith is operational.
#
# See CLAUDE.md "Service test scripts" for the convention.

set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../src/lib" && pwd)/exist-test.sh"
exist_self_elevate
exist_test_init "appsmith" EXIST_IS_SERVICES_APPSMITH
skip_if_disabled

# Appsmith CE serves the UI on :80 via its embedded nginx.
probe_service_any "appsmith UI"             appsmith 80 /                  "^(200|301|302|307)$"
probe_service     "appsmith /api/v1/users/me" appsmith 80 /api/v1/users/me 401

finish
