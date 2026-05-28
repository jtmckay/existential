#!/usr/bin/env bash
# pihole — first-time setup walkthrough.
#
# pihole is the DNS resolver that turns `<slug>.internal` into a LAN IP for
# every browser/device on the network. The whole `.internal` story doesn't
# work until devices actually use pihole as their resolver — which usually
# means pointing the home router's DNS at this machine.
#
# This script prints the configuration instructions, waits for the user to
# confirm, then probes pihole to verify it's resolving `dashy.internal`
# correctly. If anything fails, the remediation is printed and the script
# exits non-zero so the calling `./existential.sh` knows setup is incomplete.
#
# Auto-run by `./existential.sh` on first init for the pihole service.
# Re-run manually: ./existential.sh run pihole

set -euo pipefail

# Self-elevate into existential-adhoc so container DNS + /repo mount work.
if [[ -z "${IN_CONTAINER:-}" ]]; then
    _D="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    _R="$(cd "$_D/../.." && pwd)"
    exec docker compose -f "${_R}/existential-compose.yml" run --rm -it \
        --entrypoint "" existential-adhoc bash "/repo${_D#"$_R"}/exist.initial.sh"
fi

# ── Load EXIST_LOCAL_HOST_IP ─────────────────────────────────────────────────

if [ -f /repo/.env.shared ]; then
    set -a
    # shellcheck disable=SC1091
    . /repo/.env.shared
    set +a
fi

LOCAL_IP="${EXIST_LOCAL_HOST_IP:-}"
[ -n "$LOCAL_IP" ] || { echo "EXIST_LOCAL_HOST_IP is empty — run ./existential.sh first to render .env.shared" >&2; exit 1; }

hr() { printf '%0.s─' {1..56}; echo; }

# ── Step 1 — print the router DNS instructions ───────────────────────────────

echo ""
hr
echo "  Pihole — point the LAN at this machine for DNS"
hr
echo ""
echo "  pihole resolves every <slug>.internal hostname in this stack."
echo "  Until devices use pihole as their DNS resolver, NONE of those"
echo "  hostnames will resolve and the dashboard / services won't be"
echo "  reachable by their friendly names."
echo ""
echo "  ── Option A (recommended): set router DNS ──"
echo ""
echo "  1. Log into your home router's admin UI"
echo "  2. Find DNS / DHCP settings"
echo "  3. Set the PRIMARY DNS server to:"
echo ""
echo "         ${LOCAL_IP}"
echo ""
echo "  4. Leave secondary DNS blank, or set a public fallback like 1.1.1.1"
echo "  5. Save / apply. Devices may need to renew their DHCP lease."
echo ""
echo "  ── Option B: per-device DNS ──"
echo ""
echo "  If you can't reach the router, set DNS to ${LOCAL_IP} on each"
echo "  device manually (Network settings → DNS servers)."
echo ""
hr
echo ""
read -rp "  Press ENTER once router/device DNS is pointed at ${LOCAL_IP}, or type 'skip' to continue without verifying: " ack
if [[ "$ack" == "skip" ]]; then
    echo ""
    echo "  Skipped verification. Pihole .internal resolution won't work"
    echo "  until DNS is pointed at this machine — come back and re-run"
    echo "  './existential.sh run pihole' when you're ready."
    exit 0
fi

# ── Step 2 — verify pihole reachability ──────────────────────────────────────

echo ""
hr
echo "  Verifying pihole is up and resolving"
hr
echo ""

# Web UI / API reachability
if curl -sS -o /dev/null -w "%{http_code}" --max-time 5 "http://pihole:80/admin/" 2>/dev/null | grep -qE '^(200|301|302|307|401)$'; then
    echo "  ✓ pihole admin UI responds at http://pihole:80/"
else
    echo "  ✗ pihole admin UI not responding at http://pihole:80/"
    echo ""
    echo "    Remediation:"
    echo "    - docker ps | grep pihole       (is the container up?)"
    echo "    - docker logs pihole            (startup errors?)"
    echo "    - check EXIST_IS_HOSTING_PIHOLE=true in .env.shared"
    exit 1
fi

# Resolution of dashy.internal — the canonical test hostname, should resolve to LOCAL_IP.
if RESOLVED=$(getent hosts dashy.internal 2>/dev/null | awk '{print $1}' | head -1) && [ -n "$RESOLVED" ]; then
    if [ "$RESOLVED" = "$LOCAL_IP" ]; then
        echo "  ✓ dashy.internal → ${RESOLVED}   (matches EXIST_LOCAL_HOST_IP)"
    else
        echo "  ⚠ dashy.internal → ${RESOLVED}   (expected ${LOCAL_IP})"
        echo ""
        echo "    pihole resolved the hostname but to a different IP — the LOCAL/PEER"
        echo "    record in hosting/pihole/docker-compose.yml may need flipping."
    fi
else
    echo "  ✗ Could not resolve dashy.internal"
    echo ""
    echo "    This adhoc container resolves through Docker DNS first; pihole"
    echo "    is only consulted for things Docker doesn't know. The fact that"
    echo "    dashy.internal didn't resolve here suggests pihole is up but the"
    echo "    A-records didn't load. Check:"
    echo "    - docker logs pihole | grep -i 'dns hosts'"
    echo "    - hosting/pihole/docker-compose.yml FTLCONF_dns_hosts block"
    echo "    Then test resolution from a LAN device pointed at ${LOCAL_IP}:"
    echo "    - dig @${LOCAL_IP} dashy.internal +short"
fi

echo ""
hr
echo ""
echo "  Pihole admin UI:    https://pihole.internal/admin/  (or http://${LOCAL_IP}:42480/admin/)"
echo "  Admin password:     value of PIHOLE_PASSWORD in services/decree's compose (see .env)"
echo ""
echo "  Next step: confirm a LAN device can browse to https://dashy.internal/"
echo "  If it fails, the device isn't using pihole for DNS yet."
echo ""
