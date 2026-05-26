#!/usr/bin/env bash
# exist.test.sh — validate that pihole is operational.
#
# Two layers matter: the web UI (Caddy admin) and the actual DNS resolver.
# We probe both — a stack with no DNS is silently broken.
#
# See CLAUDE.md "Service test scripts" for the convention.

set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../src/lib" && pwd)/exist-test.sh"
exist_self_elevate
exist_test_init "pihole" EXIST_IS_HOSTING_PIHOLE
skip_if_disabled

# Web UI on :80. /admin/ exists when pihole is up. probe_service_any will
# implicitly verify that pihole serves a record for itself (pihole.internal).
probe_service_any "pihole /admin/" pihole 80 /admin/ "^(200|301|302|307|401)$"

# DNS listener on :53/tcp. (UDP is the canonical port but TCP is also bound.)
tcp_probe "pihole:53 DNS (tcp)" pihole 53

# Canary record — confirm pihole serves the broader .internal set, not just
# its own hostname. dashy is the conventional test target also used by
# hosting/pihole/exist.initial.sh.
probe_pihole "pihole canary record" dashy

finish
