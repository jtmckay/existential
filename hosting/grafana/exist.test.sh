#!/usr/bin/env bash
# exist.test.sh — validate that grafana is operational.
#
# See CLAUDE.md "Service test scripts" for the convention.

set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../src/lib" && pwd)/exist-test.sh"
exist_self_elevate
exist_test_init "grafana" EXIST_IS_HOSTING_GRAFANA
skip_if_disabled

# Grafana serves the UI + API on :3000. /api/health is unauthenticated.
probe_service "grafana /api/health" grafana 3000 /api/health 200

finish
