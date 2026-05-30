#!/usr/bin/env bash
# exist.test.sh — validate that it-tools is operational.
#
# See CLAUDE.md "Service test scripts" for the convention.

set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../src/test" && pwd)/exist-test.sh"
exist_self_elevate
exist_test_init "it-tools" EXIST_IS_SERVICES_IT_TOOLS
skip_if_disabled

# Pure static site served by nginx on :80.
probe_service "it-tools UI" it-tools 80 / 200

finish
