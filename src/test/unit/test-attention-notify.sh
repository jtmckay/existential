#!/usr/bin/env bash
# test-attention-notify.sh — automation/lib/attention-notify.sh sends one ntfy
# message per run that needs you (failed, or waiting on a person with no timeout), naming the
# machine and the command that continues it; a later pass sends nothing new; a
# failed `notify` run is never reported, so a broken ntfy cannot loop.
#
# Real decree, the real notify machine and script, and a fake `curl` that records
# each publish instead of sending it. Needs decree (the adhoc image has it).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
[[ -f "${REPO_DIR}/.env.exist.shared" ]] || REPO_DIR="/repo"
NOTIFIER="${REPO_DIR}/automation/lib/attention-notify.sh"

PASS=0; FAIL=0; FAIL_NAMES=()
_ok()   { printf '  PASS  %s\n' "$1"; PASS=$((PASS + 1)); }
_fail() { printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; FAIL=$((FAIL + 1)); FAIL_NAMES+=("$1"); }
check() { if eval "$2"; then _ok "$1"; else _fail "$1" "$2"; fi; }

command -v decree >/dev/null || { echo "attention-notify: needs decree (run it through ./existential.sh test unit)"; exit 1; }
unset "${!DECREE@}"   # run from inside a decree run, the caller's would leak in

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
P="${TMP}/project"
mkdir -p "$P"/.decree/machines/{boom,ask,poll}/scripts "$TMP/bin"
# notify, as the stack installs it (lib/automations/plugin.sh).
( source "${REPO_DIR}/automation/lib/automations/plugin.sh"; plugin_unpack notify "$P" ) >/dev/null
cat > "$P/.decree/machines/boom/machine.yml" << 'EOF'
name: boom
description: Exits 1.
initial: run
states:
  run:
    invoke: boom
    transitions: { done: done }
  done: { final: true }
  failed: { final: true }
EOF
cat > "$P/.decree/machines/ask/machine.yml" << 'EOF'
name: ask
description: Waits for a person.
initial: decide
states:
  decide:
    invoke:
      reply:
        question: Go on?
        notify: ask
    transitions:
      yes: { target: done, description: Go on. }
      no: { target: done, description: Stop. }
  done: { final: true }
  failed: { final: true }
EOF
cat > "$P/.decree/machines/poll/machine.yml" << 'EOF'
name: poll
description: Waits for a program, and looks again on its own.
initial: wait
states:
  wait:
    invoke:
      reply:
        question: Ready?
        notify: ask
        timeout: 1h
    transitions:
      go: { target: done, description: Ready. }
      stop: { target: done, description: Stop. }
  done: { final: true }
  failed: { final: true }
EOF
printf '#!/usr/bin/env bash\nexit 1\n' > "$P/.decree/machines/boom/scripts/boom.sh"
printf '#!/usr/bin/env bash\n' > "$P/.decree/machines/ask/scripts/ask.sh"
cp "$P/.decree/machines/ask/scripts/ask.sh" "$P/.decree/machines/poll/scripts/"
chmod +x "$P"/.decree/machines/*/scripts/*.sh
# One line per publish: its Title header, then the body on one line.
cat > "$TMP/bin/curl" << EOF
#!/usr/bin/env bash
[[ -f "$TMP/ntfy-down" ]] && exit 7
title=""; body=""
while (( \$# )); do
    case "\$1" in -H) [[ "\$2" == Title:* ]] && title="\$2"; shift ;; --data-raw) body="\$2"; shift ;; esac
    shift
done
printf '%s | %s\n' "\$title" "\${body//\$'\n'/ }" >> "$TMP/published"
EOF
chmod +x "$TMP/bin/curl"
touch "$TMP/published"

cd "$P" || exit 1
export PATH="$TMP/bin:$PATH" NTFY_USER=u NTFY_PASSWORD=p
export ATTENTION_DIR="$P/.decree/attention" ATTENTION_SEEN="$TMP/seen"
pass() { bash "$NOTIFIER" && decree daemon --once --quiet >/dev/null 2>&1; true; }

BOOM="$(echo | decree emit --machine boom)"
ASK="$(echo | decree emit --machine ask)"
echo | decree emit --machine poll >/dev/null
decree daemon --once --quiet >/dev/null 2>&1
pass
pass

check "two runs need you, two messages" "[[ \$(wc -l < '$TMP/published') == 2 ]]"
check "a failed run names its machine" "grep -qF 'Title: decree: boom failed in run' '$TMP/published'"
check "...and the command that retries it" "grep -qF 'docker exec automation decree retry ${BOOM}' '$TMP/published'"
check "a waiting run says it is waiting" "grep -qF 'Title: decree: ask is waiting for you in decide' '$TMP/published'"
check "a wait with a timeout ends without you, so it is not sent" "! grep -qF 'poll' '$TMP/published'"
check "...and how to answer" "grep -qF 'docker exec automation decree reply ${ASK}.w1 yes' '$TMP/published'"

# ntfy down: a new failure's notify run fails too, and that failure is not reported.
touch "$TMP/ntfy-down"
echo | decree emit --machine boom >/dev/null
decree daemon --once --quiet >/dev/null 2>&1
pass
check "with ntfy down, the notify run fails" "grep -lx 'machine: notify' '$P'/.decree/attention/*.md >/dev/null 2>&1"
NOTIFY_RUNS="$(ls "$P/.decree/runs" | wc -l)"
pass; pass
check "a failed notify run is never reported" "[[ \$(ls '$P/.decree/runs' | wc -l) == $NOTIFY_RUNS ]]"

# On in a fresh install: the automation container starts it, nothing to configure.
check "the automation container starts it" "grep -qx '      - ATTENTION_NOTIFY=1' '${REPO_DIR}/services/automation/docker-compose.exist.yml'"
check "the entrypoint runs it beside the daemon" "grep -qF 'bash .decree/lib/attention-notify.sh' '${REPO_DIR}/services/automation/decree/entrypoint.sh'"

[[ "${TEST_SELFCHECK:-}" == 1 ]] && _fail "selfcheck canary (deliberate failure)"

echo ""
echo "=== Results: ${PASS} passed, ${FAIL} failed ==="
if [ "$FAIL" -gt 0 ]; then
    printf 'Failed: %s\n' "${FAIL_NAMES[*]}"
    echo "--- published"; cat "$TMP/published"
    exit 1
fi
