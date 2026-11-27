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
assert_has "a logged-out Tailscale is a next step, and serves nothing" "$out" "rc=1"
out="$(es '_core_bind 0.0.0.0')"
assert_eq "...so Core listens on the network" "EXIST_CORE_BIND=0.0.0.0" "$(grep '^EXIST_CORE_BIND=' .env.shared)"
assert_has "...and says where" "$out" ":42080"
es '_core_bind 127.0.0.1' >/dev/null
assert_eq "Tailscale serving it puts it back on loopback" "EXIST_CORE_BIND=127.0.0.1" "$(grep '^EXIST_CORE_BIND=' .env.shared)"
# The host's decree project is not Core: untouched until something is on in it.
rm -rf .decree/plugins
assert_eq "with nothing on for the host, the host sync does not run" "" "$(es 'run_adhoc() { echo synced; }; _host_plugins')"
mkdir -p .decree/plugins; : > .decree/plugins/.on
assert_eq "...nor with an empty list" "" "$(es 'run_adhoc() { echo synced; }; _host_plugins')"
rm -rf .decree/plugins

# The decree image: pulled when CI published this exact build context, else built.
out="$(es 'stub() { echo "$*" >> .stub-docker; case "$1 $2" in "image inspect") return 1 ;; "pull -q") [[ "$3" == *":$(adhoc_context_hash)" ]] ;; esac; }; DOCKER_CMD=stub; ensure_adhoc_built; cat .stub-docker')"
rm -f .stub-docker
assert_has "a published image of this context is pulled" "$out" "pull -q ghcr.io/jtmckay/existential-decree:"
assert_has "...tagged as the local image" "$out" "tag ghcr.io/jtmckay/existential-decree:"
assert_eq "...and nothing is built" "" "$(grep 'compose' <<<"$out")"
out="$(es 'stub() { echo "$*" >> .stub-docker; case "$1 $2" in "image inspect") return 1 ;; "pull -q") return 1 ;; esac; }; DOCKER_CMD=stub; ensure_adhoc_built; cat .stub-docker')"
rm -f .stub-docker
assert_has "no published image: it is built here" "$out" "compose -f"
t0=$SECONDS
es 'timeout 1 sleep 5' >/dev/null
assert_eq "timeout stops a command" "yes" "$([[ $((SECONDS - t0)) -lt 4 ]] && echo yes || echo no)"

echo ""; echo "=== a worker without docker ==="
assert_eq "adhoc never passes -it, which podman-compose does not have" "0" "$(grep -c 'tty_flags=(-it)' src/utils/adhoc.sh)"
out="$(es 'command() { [[ "$2" == yq ]] && return 1; builtin command "$@"; }; _worker_needs; echo "rc=$?"')"
assert_has "a missing tool is named" "$out" "yq is not here"
assert_has "...with how to get it" "$out" "mikefarah/yq/releases/download/v"
assert_has "...and the run stops" "$out" "rc=1"
out="$(es '_SHELL_PATH=/usr/bin; _check_local_bin')"
assert_has "a .local/bin off your PATH is named with the line that adds it" "$out" 'export PATH="$HOME/.local/bin:$PATH"'
# The host plugin sync, as a worker with no engine runs it: on the host, not in adhoc.
if command -v yq >/dev/null 2>&1 && command -v decree >/dev/null 2>&1; then
    out="$(REPO_DIR="$R" "$BASH" src/plugins.sh on report_host 2>&1)"; rc=$?
    assert_eq "the host's plugins sync without adhoc" "0" "$rc"
    assert_eq "...installing the worker's report_host" "yes" "$([[ -f "${R}/.decree/machines/report_host/machine.yml" ]] && echo yes || echo no)"
    # A worker with no services never needs the image, even where an engine is,
    # and even missing a tool (_worker_without_engine names it).
    assert_eq "a worker with services on still builds" "no" "$(es '_worker_only && echo yes || echo no')"
    cp .env.shared .env.shared.keep; sed -i.bak 's/^\(EXIST_IS_[A-Z0-9_]*\)=true/\1=false/' .env.shared; rm -f .env.shared.bak
    assert_eq "a worker with none skips the engine" "yes" "$(es '_worker_only && echo yes || echo no')"
    mv .env.shared.keep .env.shared
    rm -rf "${R}/.decree/machines" "${R}/.decree/plugins" "${R}/.decree/lib"
else
    echo "  (no yq and decree here: the host sync is not run)"
fi

echo ""; echo "=== Core's setup ==="
# The plugin sync runs in adhoc (yq, decree), which a Mac host has no part in:
# a docker that writes down what it was asked stands in for it.
mkdir -p "${R}/.stub"; printf '#!/bin/sh\n[ "$1" = compose ] && echo "$*" >> "%s/.stub/asked"\nexit 0\n' "$R" > "${R}/.stub/docker"
cp "${R}/.stub/docker" "${R}/.stub/podman"   # adhoc takes podman when it is here
chmod +x "${R}/.stub/docker" "${R}/.stub/podman"; PATH="${R}/.stub:${PATH}"; export PATH
out="$("$BASH" services/automation/exist.initial.sh 2>&1)"; rc=$?
assert_eq "automation's exist.initial.sh runs" "0" "$rc"
[[ "$rc" == 0 ]] || printf '%s\n' "$out" | tail -5 | sed 's/^/        /'
assert_has "...and installs its plugins in adhoc" "$(cat "${R}/.stub/asked" 2>/dev/null)" "plugins.sh sync automation"
assert_eq "...and a second run changes nothing" "" "$("$BASH" services/automation/exist.initial.sh 2>&1)"

echo ""; echo "=== host plugins ==="
# A host plugin's script runs on the host. reporting's, taken out of its plugin
# with awk (no yq here), against a scratch host project, a curl that keeps the
# push, and a tmux that writes down what it would start (alloy only has to be
# there). test-report-host.sh covers what it sends; this covers that it runs.
H="${R}/.stub/host"; mkdir -p "${H}/rep" "${R}/.decree/machines/report_host"
touch "${R}/.decree/machines/report_host/machine.yml"
awk '/^  report\.sh: \|$/ { f = 1; next } f && /^  [^ ]/ { exit } f && /^[^ ]/ { exit } f { sub(/^    /, ""); print }' \
    automation/plugins/report_host.md > "${H}/report.sh"
cp .env.shared .env.shared.keep; echo 'EXIST_CONTROLLER=ctl.example' >> .env.shared
printf '#!/bin/sh\nfor a in "$@"; do case "$a" in @*) cp "${a#@}" "%s/body" ;; esac; done\nexit 0\n' "$H" > "${R}/.stub/curl"
printf '#!/bin/sh\n[ "$1" = has-session ] && exit 1\necho "$*" >> "%s/tmux"\n' "$H" > "${R}/.stub/tmux"
printf '#!/bin/sh\n' > "${R}/.stub/alloy"
chmod +x "${R}/.stub/curl" "${R}/.stub/tmux" "${R}/.stub/alloy"
out="$(cd "$R" && DECREE_STATE_DIR="${H}/rep" "$BASH" "${H}/report.sh" 2>&1)"; rc=$?
mv .env.shared.keep .env.shared
assert_eq "report_host runs" "0" "$rc"
[[ "$rc" == 0 ]] || printf '%s\n' "$out" | tail -5 | sed 's/^/        /'
assert_has "...and sends this host" "$(cat "${H}/body" 2>/dev/null)" '"kind":"disk"'
assert_has "...and starts alloy" "$(cat "${H}/tmux" 2>/dev/null)" "reporting-alloy"

# A host whose daemon runs another decree: a sync would take what that daemon runs.
printf '#!/bin/sh\necho "decree 0.5.0"\n' > "${R}/.stub/decree"; chmod +x "${R}/.stub/decree"
: > "${R}/.stub/asked"
mkdir -p "${R}/.decree/plugins"; echo report_host > "${R}/.decree/plugins/.on"
out="$(es 'PATH="${R}/.stub:${PATH}"; DOCKER_CMD=docker; _host_plugins')"
rm -f "${R}/.decree/plugins/.on"
assert_has "a host on another decree, with a host plugin on, is told to install this one" "$out" "the host's plugins (.decree) are left as they are"
assert_eq "...and its project is not synced" "" "$(grep 'sync host' "${R}/.stub/asked")"
rm -f "${R}/.stub/decree"

# Self-check canary: TEST_SELFCHECK=1 forces one failure so this suite's own
# FAIL→exit path is proven.
[[ "${TEST_SELFCHECK:-}" == 1 ]] && _fail "selfcheck canary (deliberate failure)"

echo ""
echo "=== Results: ${PASS} passed, ${FAIL} failed ==="
if [ "$FAIL" -gt 0 ]; then echo "Failed:"; for n in "${FAIL_NAMES[@]}"; do echo "  - $n"; done; exit 1; fi
