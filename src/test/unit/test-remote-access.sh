#!/usr/bin/env bash
# test-remote-access.sh — Tailscale is one way to reach the stack, not a prerequisite.
#
# The LAN works with nothing installed; remote access is any VPN, listed side by side
# in site/docs/hosting/vpn.md. So no prerequisite list names Tailscale, the quest's
# closing tip doesn't nag about it, and host detection still prefers a tailnet address
# for those who run one.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
[[ -f "${SRC_DIR}/quest.sh" ]] || SRC_DIR="/src"
REPO_DIR="$(cd "${SRC_DIR}/.." && pwd)"
[[ -f "${REPO_DIR}/existential.sh" ]] || REPO_DIR="/repo"

PASS=0; FAIL=0; FAIL_NAMES=()
_ok()   { printf '  PASS  %s\n' "$1"; PASS=$((PASS + 1)); }
_fail() { printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; FAIL=$((FAIL + 1)); FAIL_NAMES+=("$1"); }

# ── Prerequisites ─────────────────────────────────────────────────────────────

# The prerequisites run from the "Prerequisites" line to the first fenced block or heading.
_prereqs() { awk '/Prerequisites/{on=1} on && /^(```|## |### )/ && !/Prerequisites/{exit} on' "${REPO_DIR}/$1"; }
for f in README.md site/docs/getting-started.md site/docs/intro.md; do
    p="$(_prereqs "$f")"
    if [[ -z "$p" ]]; then
        _fail "$f has prerequisites" "no Prerequisites section found"
    elif grep -qi tailscale <<<"$p"; then
        _fail "$f prerequisites don't list Tailscale" "$p"
    else
        _ok "$f prerequisites don't list Tailscale"
    fi
done

# ── The quest's closing access tip ────────────────────────────────────────────

# _access_tip runs with only its helpers, and with no tailscale on PATH.
_tip() {
    local env="$1"
    (
        PATH="/usr/bin:/bin"
        EXIST_ENV="$env"
        _C_GREEN='' _C_YELLOW='' _C_RESET=''
        hr() { :; }
        env_get() { grep -E "^${1}=" "$EXIST_ENV" 2>/dev/null | head -1 | cut -d= -f2-; }
        will_be_active() { [[ "$(env_get "$1")" == "true" ]]; }
        eval "$(awk '/^_access_tip\(\)/,/^}/' "${SRC_DIR}/quest.sh")"
        _access_tip
    )
}

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
printf 'EXIST_DOMAIN=192-168-1-20.nip.io\nEXIST_IS_HOSTING_CADDY=true\n' > "$WORK/.env"

out="$(_tip "$WORK/.env")"
if grep -qi tailscale <<<"$out"; then
    _fail "LAN tip doesn't mention Tailscale" "$out"
else
    _ok "LAN tip doesn't mention Tailscale"
fi
if grep -q 'docs/hosting/vpn' <<<"$out"; then
    _ok "LAN tip points at the VPN docs"
else
    _fail "LAN tip points at the VPN docs" "$out"
fi

# ── Host detection still prefers a tailnet address ────────────────────────────

# _detect_host_ip <tailscale-output> — runs it against a stub tailscale on PATH.
_detect() {
    mkdir -p "$WORK/bin"
    printf '#!/bin/sh\necho "%s"\n' "$1" > "$WORK/bin/tailscale"
    chmod +x "$WORK/bin/tailscale"
    (
        PATH="$WORK/bin:$PATH"
        ip() { echo "1.1.1.1 via 192.168.1.1 dev eth0 src 192.168.1.20 uid 1000"; }
        eval "$(awk '/^_detect_host_ip\(\)/,/^}/' "${REPO_DIR}/existential.sh")"
        _detect_host_ip
    )
}

got="$(_detect 100.101.102.103)"
[[ "$got" == 100.101.102.103 ]] && _ok "tailnet address is preferred when up" \
    || _fail "tailnet address is preferred when up" "got '${got}'"
got="$(_detect '')"
[[ "$got" == 192.168.1.20 ]] && _ok "LAN address when tailscale is down" \
    || _fail "LAN address when tailscale is down" "got '${got}'"

[[ "${TEST_SELFCHECK:-}" == 1 ]] && _fail "selfcheck canary (deliberate failure)"

echo ""
echo "=== Results: ${PASS} passed, ${FAIL} failed ==="
if [ "$FAIL" -gt 0 ]; then
    printf 'Failed: %s\n' "${FAIL_NAMES[*]}"
    exit 1
fi
