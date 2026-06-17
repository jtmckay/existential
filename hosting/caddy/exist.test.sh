#!/usr/bin/env bash
# exist.test.sh — validate that caddy is operational.
#
# Caddy serves HTTPS on :443 and redirects plain HTTP on :80 up to HTTPS. We check
# :443 is up and that :80 returns a redirect (never plain content). Each service's
# own exist.test.sh checks its actual <slug>.<domain> routing.
#
# See CLAUDE.md "Service test scripts" for the convention.

set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../src/test" && pwd)/exist-test.sh"
exist_self_elevate
exist_test_init "caddy" EXIST_IS_HOSTING_CADDY
skip_if_disabled

tcp_probe "caddy:443 listening" caddy 443
http_probe_any "caddy:80 redirects to HTTPS" "http://caddy:80/" "^(301|302|308)$"

file_present "Caddyfile present"         "/repo/hosting/caddy/Caddyfile"
# Stable *.<domain> cert minted by exist.initial.sh — the pair the Caddyfile pins.
file_present "internal cert present"     "/repo/hosting/caddy/certs/internal.pem"
file_present "internal cert key present" "/repo/hosting/caddy/certs/internal-key.pem"

finish
