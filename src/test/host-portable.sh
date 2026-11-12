#!/usr/bin/env bash
# host-portable.sh — what runs on the host runs on a Mac: bash 3.2 and BSD tools.
#
# existential.sh, the helpers it sources and every exist.initial.sh run on the
# host, not in adhoc, so a Mac runs them with /bin/bash 3.2 (no mapfile, no
# ${x^^}, no local -A, and an empty "${a[@]}" is unbound under set -u), BSD sed
# (`sed -i` needs a suffix) and no `timeout`. Linux never trips on any of that,
# so this runs those pieces for real, against a scratch copy of the repo:
#
#   - with the bash that runs it (CI runs /bin/bash on macOS: 3.2, BSD tools);
#   - and, when docker is here, again under bash 3.2 (the image pinned below).
#
# Read-only: everything it writes is in the scratch copy, removed in the trap.
set -uo pipefail

BASH32_IMAGE="bash:3.2@sha256:b6252c62fc86114f93f02104a486c71e6569371d95950ea7479a2ffd6b47f16a"

if [[ "${1:-}" != --in ]]; then
    ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
    TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
    (cd "$ROOT" && git ls-files -z | tar --null -T - -cf -) | tar -xf - -C "$TMP"
    rc=0
    echo "=== host-portable: $("$BASH" --version | head -1) ==="
    "$BASH" "$TMP/src/test/host-portable.sh" --in || rc=1
    DOCKER_CMD="${DOCKER_CMD:-docker}"
    if command -v "$DOCKER_CMD" >/dev/null 2>&1; then
        rm -rf "$TMP"/volumes "$TMP"/.env.shared
        echo ""; echo "=== host-portable: bash 3.2 ==="
        # yq and decree are static binaries: the host's, where it has them, for the host sync.
        tools=()
        for t in yq decree; do
            command -v "$t" >/dev/null 2>&1 && tools+=(-v "$(command -v "$t")":/usr/local/bin/"$t":ro)
        done
        $DOCKER_CMD run --rm --user "$(id -u):$(id -g)" -v "$TMP":/r -w /r ${tools[@]+"${tools[@]}"} "$BASH32_IMAGE" \
            bash /r/src/test/host-portable.sh --in || rc=1
    else
        echo "  (no docker: bash 3.2 leg skipped; the macOS CI job runs it natively)"
    fi
    exit "$rc"
fi

R="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$R"
PASS=0; FAIL=0; FAIL_NAMES=()
_ok()   { printf '  PASS  %s\n' "$1"; PASS=$((PASS + 1)); }
_fail() { printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; FAIL=$((FAIL + 1)); FAIL_NAMES+=("$1"); }
assert_eq()  { if [[ "$2" == "$3" ]]; then _ok "$1"; else _fail "$1" "expected=$2 got=$3"; fi; }
assert_has() { if [[ "$2" == *"$3"* ]]; then _ok "$1"; else _fail "$1" "missing: $3"; fi; }
# Run a line with existential.sh's definitions loaded, in a subshell (it sets -eu).
es() { ( . ./existential.sh; set +e; eval "$1" ) 2>&1; }

grep -E '^EXIST_IS_' .env.exist.shared > .env.shared
printf 'EXIST_LOCAL_HOST_IP=\nEXIST_DOMAIN=\nEXIST_TAILNET_NAME=\n' >> .env.shared

echo ""; echo "=== existential.sh ==="
assert_eq "--help runs" "0" "$("$BASH" ./existential.sh --help >/dev/null 2>&1; echo $?)"
out="$("$BASH" ./existential.sh run 2>&1)"
assert_has "run lists each service's actions" "$out" "run automation"
out="$("$BASH" ./existential.sh run automation nope 2>&1)"
assert_has "an unknown action lists the ones there are" "$out" "  initial"
assert_eq "a folder maps to its flag" "EXIST_IS_SERVICES_CODE_SERVER" "$(es '_enable_var_for "$SCRIPT_DIR/services/code-server"')"
assert_eq "Core is enabled" "yes" "$(es 'service_is_enabled "$SCRIPT_DIR/services/automation" && echo yes')"
ip="$(es _detect_host_ip)"
if [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then _ok "the host's address is found"; else _fail "the host's address is found" "got: $ip"; fi
es _ensure_host_access >/dev/null
assert_eq "...and written to .env.shared" "EXIST_LOCAL_HOST_IP=$ip" "$(grep '^EXIST_LOCAL_HOST_IP=' .env.shared)"
assert_eq "...with a nip.io domain from it" "EXIST_DOMAIN=${ip//./-}.nip.io" "$(grep '^EXIST_DOMAIN=' .env.shared)"
assert_eq "...leaving no sed backup behind" "no" "$([[ -e .env.shared.bak ]] && echo yes || echo no)"
out="$(es 'tailscale() { echo "{\"BackendState\":\"NeedsLogin\"}"; }; _tailscale_serve_core; echo "rc=$?"')"
assert_has "a logged-out Tailscale is a next step, not a failure" "$out" "rc=0"
t0=$SECONDS
es 'timeout 1 sleep 5' >/dev/null
assert_eq "timeout stops a command" "yes" "$([[ $((SECONDS - t0)) -lt 4 ]] && echo yes || echo no)"

echo ""; echo "=== a worker without docker ==="
out="$(es 'command() { [[ "$2" == yq ]] && return 1; builtin command "$@"; }; _worker_needs; echo "rc=$?"')"
assert_has "a missing tool is named" "$out" "yq is not here"
assert_has "...with how to get it" "$out" "mikefarah/yq/releases/download/v"
assert_has "...and the run stops" "$out" "rc=1"
# The host plugin sync, as a worker with no engine runs it: on the host, not in adhoc.
if command -v yq >/dev/null 2>&1 && command -v decree >/dev/null 2>&1; then
    (REPO_DIR="$R"; . src/utils/flows.sh; plugins_turn on worker)
    out="$(REPO_DIR="$R" "$BASH" src/lib/plugin.sh sync host 2>&1)"; rc=$?
    assert_eq "the host's plugins sync without adhoc" "0" "$rc"
    assert_has "...installing the worker's reporting" "$out" "reporting installed"
    rm -rf "${R}/host"
else
    echo "  (no yq and decree here: the host sync is not run)"
fi

echo ""; echo "=== flows and Core's setup ==="
assert_eq "a flow brings the flows it needs" "nextcloud-capture transcription" \
    "$(REPO_DIR="$R"; . src/utils/flows.sh; flow_closure transcription | xargs)"
# The plugin sync runs in adhoc (yq, decree), which a Mac host has no part in:
# a docker that writes down what it was asked stands in for it.
mkdir -p "${R}/.stub"; printf '#!/bin/sh\n[ "$1" = compose ] && echo "$*" >> "%s/.stub/asked"\nexit 0\n' "$R" > "${R}/.stub/docker"
chmod +x "${R}/.stub/docker"; PATH="${R}/.stub:${PATH}"; export PATH
out="$("$BASH" services/automation/exist.initial.sh 2>&1)"; rc=$?
assert_eq "automation's exist.initial.sh runs" "0" "$rc"
[[ "$rc" == 0 ]] || printf '%s\n' "$out" | tail -5 | sed 's/^/        /'
assert_has "...and installs its plugins in adhoc" "$(cat "${R}/.stub/asked" 2>/dev/null)" "plugin.sh sync automation"
assert_eq "...and a second run changes nothing" "" "$("$BASH" services/automation/exist.initial.sh 2>&1)"

echo ""; echo "=== host plugins ==="
# A host plugin's script runs on the host. reporting's, taken out of its plugin
# with awk (no yq here), against a scratch host project and a curl that keeps
# the push. test-reporting.sh covers what it sends; this covers that it runs.
H="${R}/host"; mkdir -p "${H}/rep" "${R}/volumes/workspace_data/.decree/runs/r1"
printf '{"type":"run_finished","machine":"notify","state":"done"}\n' > "${R}/volumes/workspace_data/.decree/runs/r1/events.jsonl"
awk '/^  report: \|$/ { f = 1; next } f && /^  [^ ]/ { exit } f && /^[^ ]/ { exit } f { sub(/^    /, ""); print }' \
    automation/plugins/reporting.md > "${H}/report.sh"
echo '{"loki":"http://loki:3100"}' > "${H}/exist.json"
printf '#!/bin/sh\nfor a in "$@"; do case "$a" in @*) cp "${a#@}" "%s/body" ;; esac; done\nexit 0\n' "$H" > "${R}/.stub/curl"
chmod +x "${R}/.stub/curl"
out="$(cd "$H" && DECREE_STORE="${H}/rep" "$BASH" report.sh 2>&1)"; rc=$?
assert_eq "reporting runs" "0" "$rc"
[[ "$rc" == 0 ]] || printf '%s\n' "$out" | tail -5 | sed 's/^/        /'
assert_has "...and sends the run" "$(cat "${H}/body" 2>/dev/null)" 'notify'

# Self-check canary: TEST_SELFCHECK=1 forces one failure so this suite's own
# FAIL→exit path is proven.
[[ "${TEST_SELFCHECK:-}" == 1 ]] && _fail "selfcheck canary (deliberate failure)"

echo ""
echo "=== Results: ${PASS} passed, ${FAIL} failed ==="
if [ "$FAIL" -gt 0 ]; then echo "Failed:"; for n in "${FAIL_NAMES[@]}"; do echo "  - $n"; done; exit 1; fi
