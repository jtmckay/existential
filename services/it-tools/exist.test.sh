#!/usr/bin/env bash
# exist.test.sh — validate that it-tools is operational.
#
# See .claude/reference/testing.md for the convention.

set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../src/test" && pwd)/exist-test.sh"
exist_self_elevate
exist_test_init "it-tools" EXIST_IS_SERVICES_IT_TOOLS
skip_if_disabled

# Pure static SPA served by nginx on :80 — no API, no database, nothing
# per-request beyond disk reads. probe_service covers container DNS + Caddy +
# piHole routing; a bare 200 there is real but not enough to distinguish
# "serving it-tools" from "serving nginx's own default page" (e.g. an image
# swap or a build that dropped the SPA files but left nginx itself healthy).
probe_service "it-tools UI" it-tools 80 / 200

# Content check: the served HTML must actually be IT-Tools, not nginx's stock
# welcome page or some other app answering on :80. <title> is stable across
# upstream releases (checked against the shipped index.html).
BODY=$(curl -sS --max-time 5 "http://it-tools:80/" 2>/dev/null || true)
if [ -z "$BODY" ]; then
    fail "it-tools serves the app" \
         "no response from http://it-tools:80/" \
         "docker ps | grep it-tools; docker logs it-tools"
elif printf '%s' "$BODY" | grep -q '<title>IT Tools - Handy online tools for developers</title>'; then
    ok "it-tools serves the app"
else
    fail "it-tools serves the app" \
         "response did not contain the expected <title> — got something other than IT-Tools" \
         "docker logs it-tools; docker exec it-tools ls /usr/share/nginx/html"
fi

finish
