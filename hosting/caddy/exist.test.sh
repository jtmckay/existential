#!/usr/bin/env bash
# exist.test.sh — validate that caddy is operational.
#
# Caddy fronts every <slug>.internal route. We can't probe a specific .internal
# host from inside adhoc without DNS pointing at caddy, so we check that caddy
# itself accepts TCP on :80/:443 and responds with *some* HTTP status to a bare
# request. A 308 to HTTPS (or 421 misdirected) is healthy — proves caddy is up.
#
# See CLAUDE.md "Service test scripts" for the convention.

set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../src/test" && pwd)/exist-test.sh"
exist_self_elevate
exist_test_init "caddy" EXIST_IS_HOSTING_CADDY
skip_if_disabled

http_probe_any "caddy:80 responds"   "http://caddy:80/"  "^(200|301|302|308|404|421)$"
tcp_probe       "caddy:443 listening" caddy 443

file_present "Caddyfile present"        "/repo/hosting/caddy/Caddyfile"
file_present "cloudflare cert present"  "/repo/hosting/cloudflare/cloudflare.pem"

finish
