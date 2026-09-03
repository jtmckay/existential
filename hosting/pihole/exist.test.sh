#!/usr/bin/env bash
# exist.test.sh — validate that pihole is operational.
#
# Three layers matter: the web UI (Caddy admin), local resolution (the
# wildcard record), and upstream forwarding (everything else). We probe all
# three with real DNS queries, not just "is the container up" — a pihole that
# answers HTTP fine but can't resolve is silently broken DNS for the whole LAN.
#
# See .claude/reference/testing.md for the convention.

set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../src/test" && pwd)/exist-test.sh"
exist_self_elevate
exist_test_init "pihole" EXIST_IS_HOSTING_PIHOLE
skip_if_disabled

# Web UI on :80. /admin/ exists when pihole is up. probe_service_any will
# implicitly verify that pihole serves a record for itself (pihole.<domain>).
probe_service_any "pihole /admin/" pihole 80 /admin/ "^(200|301|302|307|401)$"

# DNS listener on :53/tcp. Cheap liveness signal only — a TCP handshake proves
# FTL is accepting connections, nothing about resolution. UDP is the protocol
# every client actually uses; the real-resolution checks below cover that.
tcp_probe "pihole:53 DNS (tcp)" pihole 53

# Canary record — confirm pihole's wildcard resolves the whole domain, not just
# its own hostname. dashy is the conventional test target. This is also the
# one check here that runs a real UDP DNS query (probe_pihole's `dig @pihole`),
# so it's what actually proves the resolver — not just the container — works.
probe_pihole "pihole canary record" dashy

# Upstream forwarding — the other half of what pihole does besides the
# wildcard. Verified against the image directly: dns.upstreams defaults to
# Google DNS with zero config, so a query for a real domain should always come
# back non-empty unless the host has no internet or upstream was misconfigured
# (see FTLCONF_dns_upstreams in docker-compose.exist.yml). Every device on the
# LAN pointed at pihole loses all non-local resolution the moment this breaks.
if command -v dig >/dev/null 2>&1; then
    _upstream_answer=$(dig @pihole +short +time=3 +tries=1 cloudflare.com 2>/dev/null | head -1 || true)
    if [ -n "$_upstream_answer" ]; then
        ok "pihole upstream forwarding"
    else
        fail "pihole upstream forwarding" \
             "pihole returned no answer for cloudflare.com" \
             "Check upstream resolvers (dns.upstreams) and that this host has internet access: docker exec pihole dig cloudflare.com; docker logs pihole"
    fi
else
    skip "pihole upstream forwarding" "dig not installed in this container"
fi

finish
