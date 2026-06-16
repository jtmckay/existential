#!/usr/bin/env bash
# exist.test.sh — validate that code-server is fully operational.
#
# See CLAUDE.md "Service test scripts" for the convention.
# Run via: ./existential.sh run code-server test  (or: ./existential.sh test)

set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../src/test" && pwd)/exist-test.sh"
exist_self_elevate
exist_test_init "code-server" EXIST_IS_SERVICES_CODE_SERVER
skip_if_disabled

# code-server serves VS Code on :8080; root redirects to the IDE.
probe_service_any "code-server root" code-server 8080 / "^(200|302|307|308)$"

finish
