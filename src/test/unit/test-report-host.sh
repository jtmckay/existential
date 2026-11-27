#!/usr/bin/env bash
# test-report-host.sh — the report_host plugin sends this host to its controller's
# Loki, https://model-gateway.<EXIST_CONTROLLER>, with curl stubbed (the push body is kept):
#
#   worker      sends disks, load and machines over HTTPS with the fleet secret, and
#               starts alloy (tmux stubbed) to ship the runs to that Loki
#   again       alloy, already running, is left alone
#   address     EXIST_CONTROLLER an address, not a domain: nothing is sent, and it fails
#   nowhere     no controller and no Loki: nothing is sent, and the run is still done
#   controller  no EXIST_CONTROLLER, Loki on: its own Loki on loopback; a new Loki
#               restarts alloy
#   no alloy    still done, and it says the runs are not shipped
#
# Everything is written under a temp dir, removed in the trap.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
[[ -f "${REPO_DIR}/.env.exist.shared" ]] || REPO_DIR="/repo"
command -v yq >/dev/null 2>&1 || { echo "skipped — yq not available (run inside existential-adhoc)"; exit 0; }

PASS=0; FAIL=0; FAIL_NAMES=()
_ok()   { printf '  PASS  %s\n' "$1"; PASS=$((PASS + 1)); }
_fail() { printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; FAIL=$((FAIL + 1)); FAIL_NAMES+=("$1"); }
assert_eq()  { if [[ "$2" == "$3" ]]; then _ok "$1"; else _fail "$1" "expected=$2 got=$3"; fi; }
assert_has() { if [[ "$2" == *"$3"* ]]; then _ok "$1"; else _fail "$1" "missing: $3"; fi; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# An install: two decree projects with a machine each, one finished run and one
# still running, and the plugin unpacked into host/ as the stack installs it.
I="${TMP}/install"
W="${I}/volumes/workspace_data/.decree"
mkdir -p "${W}/machines/notify" "${W}/machines/look_back" "${W}/runs/r1" "${W}/runs/r2"
touch "${W}/machines/notify/machine.yml" "${W}/machines/look_back/machine.yml"
printf '{"type":"transition","machine":"notify"}\n{"type":"run_finished","machine":"notify","state":"done","duration_ms":12}\n' > "${W}/runs/r1/events.jsonl"
printf '{"type":"transition","machine":"look_back"}\n' > "${W}/runs/r2/events.jsonl"
( source "${REPO_DIR}/automation/lib/plugin.sh"
  plugin_unpack report_host "${I}" ) >/dev/null
printf 'EXIST_CONTROLLER=ctl.example\nEXIST_FLEET_SECRET=s3cret\n' > "${I}/.env.shared"

# curl: a header file is kept in $TMP/header; a push keeps its body in $TMP/body.
mkdir -p "${TMP}/bin"
cat > "${TMP}/bin/curl" <<EOF
#!/usr/bin/env bash
prev=""
for a in "\$@"; do
    case "\$prev|\$a" in
        -H\|@*) cp "\${a#@}" "${TMP}/header" ;;
        *\|@*) cp "\${a#@}" "${TMP}/body"; echo "\${@: -1}" > "${TMP}/pushed-to"; exit 0 ;;
    esac
    prev="\$a"
done
EOF
chmod +x "${TMP}/bin/curl"

# tmux: each session up or not (a file per name); each start and kill is logged to $TMP/tmux.
# alloy only has to be on PATH; tmx is sourced from the install, as on a host.
cat > "${TMP}/bin/tmux" <<EOF
#!/usr/bin/env bash
case "\$1" in
    has-session) [[ -f "${TMP}/tmux-up-\${3#=}" ]] ;;
    new) touch "${TMP}/tmux-up-\$4"; echo "new \$*" >> "${TMP}/tmux" ;;
    kill-session) rm -f "${TMP}/tmux-up-\${3#=}"; echo kill >> "${TMP}/tmux" ;;
esac
EOF
printf '#!/bin/sh\n' > "${TMP}/bin/alloy"
chmod +x "${TMP}/bin/tmux" "${TMP}/bin/alloy"
# The engine, either name: two containers running.
# Two services (a restart policy), an adhoc run (none), decree-go-rest (none, but
# exist.watch=true) and Strata (exist.watch=false): only those meant to stay up are reported.
cat > "${TMP}/bin/podman" <<'STUB'
#!/bin/sh
[ "$1" = ps ] && { echo a1; echo a2; echo a3; echo a4; echo a5; exit 0; }
[ "$1" = inspect ] && printf '%s\n' '/loki grafana/loki:3.5 unless-stopped <no value>' \
    '/ntfy binwiederhier/ntfy:v2 always <no value>' '/existential-adhoc-run-1 decree no <no value>' \
    '/decree-go-rest go-rest no true' '/ai-box-strata strata on-failure false'
exit 0
STUB
cp "${TMP}/bin/podman" "${TMP}/bin/docker"; chmod +x "${TMP}/bin/podman" "${TMP}/bin/docker"
# What plugin sync wrote: one plugin in the automation project (the host's own is unpacked above).
mkdir -p "${W}/plugins"
touch "${W}/plugins/look_back.md"
# An active cron, as a plugin installs it.
mkdir -p "${W}/machines/look_back/cron"
printf -- '---\ncron: "0 21 * * SUN"\nmachine: look_back\nparams:\n  period: week\n---\n\nEvery Sunday.\n' > "${W}/machines/look_back/cron/look-back-weekly.md"
mkdir -p "${I}/services/automation/decree"
cp "${REPO_DIR}/services/automation/decree/tmx.sh" "${I}/services/automation/decree/"

report() {  # [PATH]
    rm -f "${TMP}/body" "${TMP}/pushed-to"
    (cd "${I}" && PATH="${1:-${TMP}/bin:${PATH}}" DECREE_STATE_DIR="${I}/.decree/machines/report_host/state" \
        bash .decree/machines/report_host/scripts/report.sh 2>&1)
}
started() { grep -c '^new ' "${TMP}/tmux" 2>/dev/null || true; }
field() { sed -n "s/.*\"$1\":\"\([^\"]*\)\".*/\1/p"; }
lines() { yq -p json -o yaml -r ".streams[] | select(.stream.kind == \"$1\") | .values[][1]" "${TMP}/body" 2>/dev/null; }

echo ""; echo "=== worker ==="
out="$(report)"; rc=$?
assert_eq "it ends done" "0" "$rc"
assert_eq "it pushes to the controller's Loki, over HTTPS through its Caddy" "https://model-gateway.ctl.example/loki/api/v1/push" "$(cat "${TMP}/pushed-to" 2>/dev/null)"
assert_eq "...with the fleet secret as the key, from a file" "Authorization: Bearer s3cret" "$(cat "${TMP}/header" 2>/dev/null)"
assert_eq "...which only its owner reads" "600" "$(stat -c %a "${I}/.decree/machines/report_host/state/loki-header" 2>/dev/null || stat -f %Lp "${I}/.decree/machines/report_host/state/loki-header")"
assert_eq "the body is JSON Loki takes" "ok" "$(yq -p json -o yaml '.streams[0].stream.job' "${TMP}/body" >/dev/null 2>&1 && echo ok)"
assert_has "every line names this host" "$(yq -p json -o yaml -r '.streams[].stream.host' "${TMP}/body" | sort -u)" "$(hostname -s 2>/dev/null || hostname)"
assert_eq "a line per installed machine, in every project" "look_back notify report_host" "$(lines machine | field machine | sort | xargs)"
assert_eq "a line per installed plugin, with its project" "automation look_back,host report_host" "$(lines plugin | while read -r l; do echo "$(field project <<<"$l") $(field plugin <<<"$l")"; done | sort | paste -sd, -)"
assert_eq "a line per active cron, named by the machine it runs, with its schedule" \
    '{"project":"automation","machine":"look_back","schedule":"0 21 * * SUN"}' "$(lines cron | grep look_back)"
assert_eq "a line per container meant to stay up" "decree-go-rest loki ntfy" "$(lines container | field name | sort | xargs)"
assert_has "...with its image" "$(lines container)" '"image":"grafana/loki:3.5"'
assert_eq "no run line: alloy ships the runs" "" "$(lines run)"
assert_has "the disks it has" "$(lines disk | head -1)" '"avail_kb":'
assert_eq ".../ among them, by that name" "/" "$(lines disk | field mount | grep -x /)"
assert_has "its CPU and RAM" "$(lines load)" '"mem_total_kb":'
assert_eq "it starts alloy, once" "1" "$(started)"
assert_has "...in its own tmux session" "$(cat "${TMP}/tmux")" "-s reporting-alloy"
assert_has "...shipping to the same Loki" "$(cat "${TMP}/tmux")" "EXIST_LOKI='https://model-gateway.ctl.example/loki/api/v1/push'"
assert_has "...this install's runs" "$(cat "${TMP}/tmux")" "EXIST_REPO='$(cd "$I" && pwd)'"
assert_has "...with the config the plugin ships" "$(cat "${TMP}/tmux")" "'.decree/lib/reporting/decree.alloy'"
assert_has "it says so" "$out" "runs shipped live by alloy"
if command -v alloy >/dev/null 2>&1 && [[ "$(command -v alloy)" != "${TMP}/bin/alloy" ]]; then
    assert_eq "the config is one alloy reads" "0" "$(alloy fmt "${I}/.decree/lib/reporting/decree.alloy" >/dev/null 2>&1; echo $?)"
fi

echo ""; echo "=== again ==="
report >/dev/null
assert_eq "alloy, running, is left alone" "1" "$(started)"
assert_eq "...and the machines are sent every time" "3" "$(lines machine | wc -l | tr -d ' ')"

echo ""; echo "=== address ==="
printf 'EXIST_CONTROLLER=192.168.1.10\nEXIST_FLEET_SECRET=s3cret\n' > "${I}/.env.shared"
out="$(report)"; rc=$?
assert_eq "an address, not a domain: it fails" "1" "$rc"
assert_eq "...and nothing is sent, the secret least of all" "no" "$([[ -f "${TMP}/body" ]] && echo yes || echo no)"
assert_has "...and it says why" "$out" "is an address"

echo ""; echo "=== nowhere ==="
find "${I}/.decree/machines/report_host/state/" -mindepth 1 -delete
printf 'EXIST_CONTROLLER=\n' > "${I}/.env.shared"
out="$(report)"; rc=$?
assert_eq "no controller named: still done" "0" "$rc"
assert_eq "...and nothing sent" "no" "$([[ -f "${TMP}/body" ]] && echo yes || echo no)"
assert_has "...and it says why" "$out" "no controller named"

echo ""; echo "=== controller ==="
printf 'EXIST_CONTROLLER=\nEXIST_IS_HOSTING_LOKI=true\n' > "${I}/.env.shared"
report >/dev/null
assert_eq "a controller pushes to its own Loki, on loopback" "http://127.0.0.1:43100/loki/api/v1/push" "$(cat "${TMP}/pushed-to" 2>/dev/null)"
assert_eq "...and a new Loki restarts alloy" "kill" "$(tail -2 "${TMP}/tmux" | head -1)"
assert_has "...on that Loki" "$(tail -1 "${TMP}/tmux")" "EXIST_LOKI='http://127.0.0.1:43100/loki/api/v1/push'"
assert_eq "no ntfy here: no notify-relay" "0" "$(grep -c 's notify-relay' "${TMP}/tmux")"
printf 'EXIST_CONTROLLER=\nEXIST_IS_HOSTING_LOKI=true\nEXIST_IS_SERVICES_NTFY=true\n' > "${I}/.env.shared"
report >/dev/null
assert_has "the controller with ntfy starts notify-relay" "$(cat "${TMP}/tmux")" "-s notify-relay"
assert_has "...with the relay the plugin ships" "$(cat "${TMP}/tmux")" "'.decree/lib/reporting/relay.sh'"

echo ""; echo "=== no alloy ==="
rm -f "${TMP}/bin/alloy"
out="$(report "${TMP}/bin:/usr/bin:/bin")"; rc=$?
assert_eq "no alloy: still done" "0" "$rc"
assert_has "...and it says the runs are not shipped" "$out" "alloy is not on PATH"

[[ "${TEST_SELFCHECK:-}" == 1 ]] && _fail "selfcheck canary (deliberate failure)"

echo ""
echo "=== Results: ${PASS} passed, ${FAIL} failed ==="
for n in "${FAIL_NAMES[@]+"${FAIL_NAMES[@]}"}"; do echo "  ✗ $n"; done
[[ "$FAIL" -eq 0 ]]
