#!/usr/bin/env bash
# test-reporting.sh — the reporting plugin sends this host to the Loki its
# controller names, with curl stubbed (the push body is kept, the controller's
# answer is a file):
#
#   worker      asks the controller, sends disks, load and machines, and starts
#               alloy (tmux stubbed) to ship the runs to that Loki
#   again       alloy, already running, is left alone
#   away        the controller does not answer: the Loki it gave last time is used
#   nowhere     the controller, naming no Loki: nothing is sent, and the run is still done
#   controller  no EXIST_CONTROLLER: this is it, and reads host/exist.json itself;
#               a new Loki restarts alloy
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
mkdir -p "${W}/machines" "${W}/runs/r1" "${W}/runs/r2"
touch "${W}/machines/notify.yml" "${W}/machines/look_back.yml"
printf '{"type":"transition","machine":"notify"}\n{"type":"run_finished","machine":"notify","state":"done","duration_ms":12}\n' > "${W}/runs/r1/events.jsonl"
printf '{"type":"transition","machine":"look_back"}\n' > "${W}/runs/r2/events.jsonl"
( source "${REPO_DIR}/automation/lib/automations/registry.sh"; source "${REPO_DIR}/automation/lib/automations/plugin.sh"
  plugin_unpack reporting "${I}/host" ) >/dev/null
printf 'EXIST_CONTROLLER=ctl\n' > "${I}/.env.shared"

# curl: a GET of the controller prints $TMP/answer (fails without one); a push
# keeps its body in $TMP/body.
mkdir -p "${TMP}/bin"
cat > "${TMP}/bin/curl" <<EOF
#!/usr/bin/env bash
for a in "\$@"; do
    case "\$a" in
        @*) cp "\${a#@}" "${TMP}/body"; echo "\${@: -1}" > "${TMP}/pushed-to"; exit 0 ;;
    esac
done
[[ -f "${TMP}/answer" ]] && cat "${TMP}/answer" || exit 7
EOF
chmod +x "${TMP}/bin/curl"

# tmux: one session, up or not; each start and kill is logged to $TMP/tmux.
# alloy only has to be on PATH; tmx is sourced from the install, as on a host.
cat > "${TMP}/bin/tmux" <<EOF
#!/usr/bin/env bash
case "\$1" in
    has-session) [[ -f "${TMP}/tmux-up" ]] ;;
    new) touch "${TMP}/tmux-up"; echo "new \$*" >> "${TMP}/tmux" ;;
    kill-session) rm -f "${TMP}/tmux-up"; echo kill >> "${TMP}/tmux" ;;
esac
EOF
printf '#!/bin/sh\n' > "${TMP}/bin/alloy"
chmod +x "${TMP}/bin/tmux" "${TMP}/bin/alloy"
# The engine, either name: two containers running.
printf '#!/bin/sh\n[ "$1" = ps ] && printf "loki grafana/loki:3.5\\nntfy binwiederhier/ntfy:v2\\n"\n' > "${TMP}/bin/podman"
cp "${TMP}/bin/podman" "${TMP}/bin/docker"; chmod +x "${TMP}/bin/podman" "${TMP}/bin/docker"
# What plugin sync installed: one plugin in the automation project, the host's own.
mkdir -p "${W}/applied/plugins" "${I}/host/.decree/applied/plugins"
touch "${W}/applied/plugins/look_back.md" "${I}/host/.decree/applied/plugins/reporting.md"
# An active cron, as a plugin installs it.
mkdir -p "${W}/cron"
printf -- '---\ncron: "0 21 * * SUN"\nmachine: look_back\nparams:\n  period: week\n---\n\nEvery Sunday.\n' > "${W}/cron/look-back-weekly.md"
mkdir -p "${I}/services/automation/decree"
cp "${REPO_DIR}/services/automation/decree/tmx.sh" "${I}/services/automation/decree/"

report() {  # [PATH]
    rm -f "${TMP}/body" "${TMP}/pushed-to"
    (cd "${I}/host" && PATH="${1:-${TMP}/bin:${PATH}}" DECREE_STORE="${I}/host/.decree/store/reporting" \
        DECREE_LIB="${I}/host/.decree/lib" bash .decree/scripts/reporting/report.sh 2>&1)
}
started() { grep -c '^new ' "${TMP}/tmux" 2>/dev/null || true; }
field() { sed -n "s/.*\"$1\":\"\([^\"]*\)\".*/\1/p"; }
lines() { yq -p json -o yaml -r ".streams[] | select(.stream.kind == \"$1\") | .values[][1]" "${TMP}/body" 2>/dev/null; }

echo ""; echo "=== worker ==="
echo '{"loki": "http://loki-box:3100"}' > "${TMP}/answer"
out="$(report)"; rc=$?
assert_eq "it ends done" "0" "$rc"
assert_eq "it pushes to the Loki the controller names" "http://loki-box:3100/loki/api/v1/push" "$(cat "${TMP}/pushed-to" 2>/dev/null)"
assert_eq "the body is JSON Loki takes" "ok" "$(yq -p json -o yaml '.streams[0].stream.job' "${TMP}/body" >/dev/null 2>&1 && echo ok)"
assert_has "every line names this host" "$(yq -p json -o yaml -r '.streams[].stream.host' "${TMP}/body" | sort -u)" "$(hostname -s 2>/dev/null || hostname)"
assert_eq "a line per installed machine, in every project" "look_back notify reporting" "$(lines machine | field machine | sort | xargs)"
assert_eq "a line per installed plugin, with its project" "automation look_back,host reporting" "$(lines plugin | while read -r l; do echo "$(field project <<<"$l") $(field plugin <<<"$l")"; done | sort | paste -sd, -)"
assert_eq "a line per active cron, with its schedule and machine" \
    '{"project":"automation","cron":"look-back-weekly","schedule":"0 21 * * SUN","machine":"look_back"}' "$(lines cron | grep look-back-weekly)"
assert_eq "a line per running container" "loki ntfy" "$(lines container | field name | sort | xargs)"
assert_has "...with its image" "$(lines container)" '"image":"grafana/loki:3.5"'
assert_eq "no run line: alloy ships the runs" "" "$(lines run)"
assert_has "the disks it has" "$(lines disk | head -1)" '"avail_kb":'
assert_eq ".../ among them, by that name" "/" "$(lines disk | field mount | grep -x /)"
assert_has "its CPU and RAM" "$(lines load)" '"mem_total_kb":'
assert_eq "it starts alloy, once" "1" "$(started)"
assert_has "...in its own tmux session" "$(cat "${TMP}/tmux")" "-s reporting-alloy"
assert_has "...shipping to the same Loki" "$(cat "${TMP}/tmux")" "EXIST_LOKI='http://loki-box:3100/loki/api/v1/push'"
assert_has "...this install's runs" "$(cat "${TMP}/tmux")" "EXIST_REPO='$(cd "$I" && pwd)'"
assert_has "...with the config the plugin ships" "$(cat "${TMP}/tmux")" "${I}/host/.decree/lib/reporting/decree.alloy"
assert_has "it says so" "$out" "runs shipped live by alloy"
if command -v alloy >/dev/null 2>&1 && [[ "$(command -v alloy)" != "${TMP}/bin/alloy" ]]; then
    assert_eq "the config is one alloy reads" "0" "$(alloy fmt "${I}/host/.decree/lib/reporting/decree.alloy" >/dev/null 2>&1; echo $?)"
fi

echo ""; echo "=== again ==="
report >/dev/null
assert_eq "alloy, running, is left alone" "1" "$(started)"
assert_eq "...and the machines are sent every time" "3" "$(lines machine | wc -l | tr -d ' ')"

echo ""; echo "=== away ==="
rm -f "${TMP}/answer"
report >/dev/null
assert_eq "an unreachable controller: the Loki it gave last time" "http://loki-box:3100/loki/api/v1/push" "$(cat "${TMP}/pushed-to" 2>/dev/null)"

echo ""; echo "=== nowhere ==="
rm -rf "${I}/host/.decree/store/reporting"
printf 'EXIST_CONTROLLER=\n' > "${I}/.env.shared"
out="$(report)"; rc=$?
assert_eq "no Loki named: still done" "0" "$rc"
assert_eq "...and nothing sent" "no" "$([[ -f "${TMP}/body" ]] && echo yes || echo no)"
assert_has "...and it says why" "$out" "no Loki named"

echo ""; echo "=== controller ==="
printf 'EXIST_CONTROLLER=\n' > "${I}/.env.shared"
echo '{"loki":"http://127.0.0.1:43100"}' > "${I}/host/exist.json"
report >/dev/null
assert_eq "a controller reads host/exist.json" "http://127.0.0.1:43100/loki/api/v1/push" "$(cat "${TMP}/pushed-to" 2>/dev/null)"
assert_eq "...and a new Loki restarts alloy" "kill" "$(tail -2 "${TMP}/tmux" | head -1)"
assert_has "...on that Loki" "$(tail -1 "${TMP}/tmux")" "EXIST_LOKI='http://127.0.0.1:43100/loki/api/v1/push'"
assert_eq "no ntfy here: no notify-relay" "0" "$(grep -c 's notify-relay' "${TMP}/tmux")"
printf 'EXIST_CONTROLLER=\nEXIST_IS_SERVICES_NTFY=true\n' > "${I}/.env.shared"
rm -f "${TMP}/tmux-up"; report >/dev/null
assert_has "the controller with ntfy starts notify-relay" "$(cat "${TMP}/tmux")" "-s notify-relay"
assert_has "...with the relay the plugin ships" "$(cat "${TMP}/tmux")" "${I}/host/.decree/lib/reporting/relay.sh"

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
