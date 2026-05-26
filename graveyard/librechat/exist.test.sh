#!/usr/bin/env bash
# exist.test.sh — validate that LibreChat is fully operational.
#
# See CLAUDE.md "Service test scripts" for the convention.

set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../src/lib" && pwd)/exist-test.sh"
exist_self_elevate
exist_test_init "librechat" EXIST_IS_AI_LIBRECHAT
skip_if_disabled

# LibreChat client (nginx) fronts the UI on :80; the API runs on :3080.
# Probe both — a healthy stack needs both up.
#
# Caddy routes librechat.internal -> librechat-client:80, so the .internal /
# public probes target the slug (librechat), while the direct probe hits the
# real container name (librechat-client). The API has no caddy block — direct
# only.
http_probe_any "librechat-client UI via librechat-client:80" \
               "http://librechat-client:80/" "^(200|301|302)$"
probe_caddy_any "librechat-client UI" librechat / "^(200|301|302)$"

http_probe "librechat-api /health" "http://librechat-api:3080/health" 200

finish
