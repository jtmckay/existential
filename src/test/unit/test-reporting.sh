#!/usr/bin/env bash
# test-reporting.sh — the reporting plugin sends this host to the Loki its
# controller names, with curl stubbed (the push body is kept, the controller's
# answer is a file):
#
#   worker      asks the controller, sends disks, machines and finished runs
#   again       a run already sent is not sent twice
#   away        the controller does not answer: the Loki it gave last time is used
#   nowhere     the controller, naming no Loki: nothing is sent, and the run is still done
#   controller  no EXIST_CONTROLLER: this is it, and reads host/exist.json itself
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

report() {
    rm -f "${TMP}/body" "${TMP}/pushed-to"
    (cd "${I}/host" && PATH="${TMP}/bin:${PATH}" DECREE_STORE="${I}/host/.decree/store/reporting" \
        bash .decree/scripts/reporting/report.sh 2>&1)
}
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
assert_eq "a finished run is sent, with its project; a running one is not" "automation notify done" \
    "$(lines run | field project) $(lines run | field machine) $(lines run | field state)"
assert_has "the disks it has" "$(lines disk | head -1)" '"avail_kb":'
assert_has "it says what it sent" "$out" "1 runs"

echo ""; echo "=== again ==="
sleep 1; touch "${W}/machines/notify.yml"
report >/dev/null
assert_eq "a run already sent is not sent again" "" "$(lines run)"
assert_eq "...but the machines are, every time" "3" "$(lines machine | wc -l | tr -d ' ')"

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
assert_eq "...and sends every run the first time" "1" "$(lines run | wc -l | tr -d ' ')"

[[ "${TEST_SELFCHECK:-}" == 1 ]] && _fail "selfcheck canary (deliberate failure)"

echo ""
echo "=== Results: ${PASS} passed, ${FAIL} failed ==="
for n in "${FAIL_NAMES[@]+"${FAIL_NAMES[@]}"}"; do echo "  ✗ $n"; done
[[ "$FAIL" -eq 0 ]]
