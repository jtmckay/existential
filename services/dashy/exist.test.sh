#!/usr/bin/env bash
# exist.test.sh — validate that dashy is operational.
#
# See CLAUDE.md "Service test scripts" for the convention.

set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../src/lib" && pwd)/exist-test.sh"
exist_self_elevate
exist_test_init "dashy" EXIST_IS_SERVICES_DASHY
skip_if_disabled

# dashy serves the static dashboard on :8080.
probe_service "dashy UI" dashy 8080 / 200

# The config file is mounted at /app/user-data/conf.yml. If it's not readable
# (typo / bad mount), dashy still serves but shows the default landing page.
file_present "dashy-conf.yml present" "/repo/services/dashy/dashy-conf.yml"

finish
