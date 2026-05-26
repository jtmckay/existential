#!/usr/bin/env bash
# exist.test.sh — validate that portainer is operational.
#
# See CLAUDE.md "Service test scripts" for the convention.

set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../src/lib" && pwd)/exist-test.sh"
exist_self_elevate
exist_test_init "portainer" EXIST_IS_HOSTING_PORTAINER
skip_if_disabled

# Portainer serves an HTTPS UI on :9443 with a self-signed cert (so -k).
# Caddy fronts portainer.internal -> https://portainer:9443; the caddy probe
# below tests that routing leg without needing -k itself (probe_caddy already
# does so for caddy's own .internal cert).
http_probe "portainer /api/status (direct)" \
           "https://portainer:9443/api/status" 200 5 -k
probe_caddy "portainer /api/status" portainer /api/status 200

finish
