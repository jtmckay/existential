#!/usr/bin/env bash
# test-remote-access.sh — Core is reached over Tailscale; the Caddy add-on is the other path.
#
# existential.sh serves code-server on 443 and ntfy on 8443 of this host's tailnet name with
# `tailscale serve`, once each however often it runs, and never runs sudo or fails when
# Tailscale is missing or not set up yet: it prints the next step. Core publishes its ports
# on loopback only. Host detection still prefers a tailnet address, for Caddy's nip.io domain.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
[[ -f "${SRC_DIR}/flows.sh" ]] || SRC_DIR="/src"
REPO_DIR="$(cd "${SRC_DIR}/.." && pwd)"
[[ -f "${REPO_DIR}/existential.sh" ]] || REPO_DIR="/repo"

PASS=0; FAIL=0; FAIL_NAMES=()
_ok()   { printf '  PASS  %s\n' "$1"; PASS=$((PASS + 1)); }
_fail() { printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; FAIL=$((FAIL + 1)); FAIL_NAMES+=("$1"); }
_has()  { if grep -qF -- "$3" <<<"$2"; then _ok "$1"; else _fail "$1" "missing '$3' in: $2"; fi; }
_lacks() { if grep -qF -- "$3" <<<"$2"; then _fail "$1" "unexpected '$3' in: $2"; else _ok "$1"; fi; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# ── Core binds loopback only ──────────────────────────────────────────────────

for svc in code-server ntfy automation; do
    f="${REPO_DIR}/services/${svc}/docker-compose.exist.yml"
    bad="$(awk '/^ *ports:/{on=1; next} on && /^ *- /{print; next} {on=0}' "$f" | grep -v '"127\.0\.0\.1:' || true)"
    if [[ -z "$bad" ]]; then _ok "${svc} publishes only on 127.0.0.1"; else _fail "${svc} publishes only on 127.0.0.1" "$bad"; fi
done

# ── tailscale serve ───────────────────────────────────────────────────────────

# A stub tailscale: `status --json` prints $TS_STATUS; `serve --bg --https=P T` sets the
# one handler for port P (as tailscaled does) and logs the call; `serve status --json`
# renders what is set. TS_SERVE_FAIL makes serve refuse, like a missing operator.
mkdir -p "$WORK/bin"
cat > "$WORK/bin/tailscale" <<'EOF'
#!/usr/bin/env bash
case "$1 $2" in
    "status --json") printf '%s\n' "$TS_STATUS" ;;
    "serve status")
        sep=''; printf '{"Web":{'
        while read -r p t; do printf '%s"%s:%s": {"Handlers": {"/": {"Proxy": "%s"}}}' "$sep" "$TS_NAME" "$p" "$t"; sep=,; done < <(cat "$TS_STATE" 2>/dev/null)
        printf '}}\n' ;;
    "serve --bg")
        [[ -n "${TS_SERVE_FAIL:-}" ]] && { echo "Access denied: serve config denied" >&2; exit 1; }
        p="${3#--https=}"
        echo "$*" >> "$TS_CALLS"
        { grep -v "^${p} " "$TS_STATE" 2>/dev/null || true; echo "$p $4"; } > "$TS_STATE.new"; mv "$TS_STATE.new" "$TS_STATE" ;;
    *) exit 1 ;;
esac
EOF
printf '#!/bin/sh\ntouch "%s/sudo-ran"\n' "$WORK" > "$WORK/bin/sudo"
chmod +x "$WORK/bin/tailscale" "$WORK/bin/sudo"
# A PATH with the tools the function uses and no tailscale, whatever this host has.
mkdir -p "$WORK/nobin"
for t in bash grep sed cut head tr timeout cat mv; do ln -s "$(command -v "$t")" "$WORK/nobin/$t"; done

export TS_NAME=box.tail1234.ts.net TS_STATE="$WORK/serve" TS_CALLS="$WORK/calls"
RUNNING="{\"BackendState\": \"Running\", \"Self\": {\"DNSName\": \"${TS_NAME}.\"}, \"CertDomains\": [\"${TS_NAME}\"]}"
NO_HTTPS="{\"BackendState\": \"Running\", \"Self\": {\"DNSName\": \"${TS_NAME}.\"}, \"CertDomains\": null}"

printf 'EXIST_IS_SERVICES_CODE_SERVER=true\nEXIST_IS_SERVICES_NTFY=true\nEXIST_TAILNET_NAME=\n' > "$WORK/.env.shared"
cp "$WORK/.env.shared" "$WORK/env.fresh"

# _serve <path> — runs _tailscale_serve_core as existential.sh does (set -euo pipefail).
_serve() {
    local rc=0
    ( set -euo pipefail
      eval "$(awk '/^_tailscale_serve_core\(\)/,/^}/; /^_tailscale_serve_steps\(\)/,/^}/' "${REPO_DIR}/existential.sh")"
      PATH="$1"; SCRIPT_DIR="$WORK"
      _tailscale_serve_core ) 2>&1 || rc=$?
    echo "rc=$rc"
}

# No binary: carries on, says what Core needs and the alternative.
out="$(_serve "$WORK/nobin")"
_has "no tailscale: exits 0" "$out" "rc=0"
_has "no tailscale: says Core needs it" "$out" "Core needs Tailscale"
_has "no tailscale: says how to install it" "$out" "https://tailscale.com/download"
_has "no tailscale: names the Caddy add-on" "$out" "EXIST_IS_HOSTING_CADDY=true"

# Up, but HTTPS not enabled for the tailnet: the exact steps, no serve, no sudo.
out="$(TS_STATUS="$NO_HTTPS" _serve "$WORK/bin:$WORK/nobin")"
_has "no HTTPS yet: exits 0" "$out" "rc=0"
_has "no HTTPS yet: points at the admin console" "$out" "MagicDNS and HTTPS Certificates"
_has "no HTTPS yet: gives the operator command" "$out" 'sudo tailscale set --operator=$USER'
[[ ! -e "$TS_CALLS" ]] && _ok "no HTTPS yet: serves nothing" || _fail "no HTTPS yet: serves nothing" "$(cat "$TS_CALLS")"

# Serve refused (no operator): carries on with the steps.
out="$(TS_STATUS="$RUNNING" TS_SERVE_FAIL=1 _serve "$WORK/bin:$WORK/nobin")"
_has "serve refused: exits 0" "$out" "rc=0"
_has "serve refused: shows why" "$out" "Access denied"
_has "serve refused: gives the operator command" "$out" "--operator="
grep -qx "EXIST_TAILNET_NAME=" "$WORK/.env.shared" && _ok "serve refused: EXIST_TAILNET_NAME stays blank" \
    || _fail "serve refused: EXIST_TAILNET_NAME stays blank" "$(cat "$WORK/.env.shared")"

# Up with HTTPS, run twice: code-server on 443 and ntfy on 8443, once each.
out="$(TS_STATUS="$RUNNING" _serve "$WORK/bin:$WORK/nobin")"
_has "serving: exits 0" "$out" "rc=0"
_has "serving: prints code-server's URL" "$out" "https://${TS_NAME}"
_has "serving: prints ntfy's URL" "$out" "https://${TS_NAME}:8443"
out="$(TS_STATUS="$RUNNING" _serve "$WORK/bin:$WORK/nobin")"
_has "second run: exits 0" "$out" "rc=0"
status="$(TS_STATE="$TS_STATE" "$WORK/bin/tailscale" serve status --json)"
_has "serve status: code-server on 443" "$status" "\"${TS_NAME}:443\": {\"Handlers\": {\"/\": {\"Proxy\": \"http://127.0.0.1:42080\"}}}"
_has "serve status: ntfy on 8443" "$status" "\"${TS_NAME}:8443\": {\"Handlers\": {\"/\": {\"Proxy\": \"http://127.0.0.1:44680\"}}}"
calls="$(cat "$TS_CALLS" 2>/dev/null | wc -l | tr -d " ")"
[[ "$calls" == 2 ]] && _ok "two runs set each port once" || _fail "two runs set each port once" "$(cat "$TS_CALLS")"
_has "uses --bg, which persists across reboots" "$(cat "$TS_CALLS")" "serve --bg --https=443 http://127.0.0.1:42080"
_has "EXIST_TAILNET_NAME is filled in" "$(cat "$WORK/.env.shared")" "EXIST_TAILNET_NAME=${TS_NAME}"
[[ ! -e "$WORK/sudo-ran" ]] && _ok "never runs sudo" || _fail "never runs sudo"

# Neither web app enabled: nothing to say.
printf 'EXIST_IS_SERVICES_AUTOMATION=true\n' > "$WORK/.env.shared"
out="$(_serve "$WORK/nobin")"
[[ "$out" == "rc=0" ]] && _ok "no Core web app enabled: silent" || _fail "no Core web app enabled: silent" "$out"

# ── Host detection still prefers a tailnet address (Caddy's nip.io) ───────────

# _detect_host_ip <tailscale-output> — runs it against a stub tailscale on PATH.
_detect() {
    mkdir -p "$WORK/ipbin"
    printf '#!/bin/sh\necho "%s"\n' "$1" > "$WORK/ipbin/tailscale"
    chmod +x "$WORK/ipbin/tailscale"
    (
        PATH="$WORK/ipbin:$PATH"
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
