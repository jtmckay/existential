#!/usr/bin/env bash
# test-capture.sh — automation/lib/capture/, the capture stream's one writer.
#
#   redaction  a prompt with an Anthropic key and password=hunter2 keeps neither
#              value and keeps the rest; every other kind gets its own marker.
#   shape      one {ts, source, context, session, text} line per prompt, nothing else
#              of a hook's input (no transcript); empty text writes nothing; two
#              prompts of one session share its id, another session's differs.
#   failure    an unwritable stream exits 0 and lands in errors.log.
#   detached   the default write happens after capture.sh has already exited.
#   install    the Claude Code hook is added once, survives a second install,
#              leaves the user's other settings alone, and uninstall removes it.
#   webhook    POST /capture routes to the capture machine, whose script appends
#              the posted source and text.
#
# Key-shaped literals are split ('AKIA''...') so the secret guards never see one.
# Everything is written under a temp dir, removed in the trap.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
[[ -f "${REPO_DIR}/.env.exist.shared" ]] || REPO_DIR="/repo"
CAPTURE="${REPO_DIR}/automation/lib/capture/capture.sh"

PASS=0; FAIL=0; FAIL_NAMES=()
_ok()   { printf '  PASS  %s\n' "$1"; PASS=$((PASS + 1)); }
_fail() { printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; FAIL=$((FAIL + 1)); FAIL_NAMES+=("$1"); }
assert_eq() { if [[ "$2" == "$3" ]]; then _ok "$1"; else _fail "$1" "expected=$2 got=$3"; fi; }
assert_has()  { if [[ "$2" == *"$3"* ]]; then _ok "$1"; else _fail "$1" "missing: $3"; fi; }
assert_lacks() { if [[ "$2" != *"$3"* ]]; then _ok "$1"; else _fail "$1" "found: $3"; fi; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# cap <dir> <source> <stdin>: a synchronous capture, then the last line written.
cap() {
    CAPTURE_DIR="$1" CAPTURE_HOST=test CAPTURE_WAIT=1 bash "$CAPTURE" "$2" <<<"$3"
    tail -n1 "$1"/*-test.jsonl 2>/dev/null
}

# ── redaction ─────────────────────────────────────────────────────────────────
D="${TMP}/r"
line="$(cap "$D" claude-code "$(jq -n '{prompt: "ship it with sk-ant-api03-Zx9_abc-DEF and password=hunter2 please", cwd: "/workspace/p", session_id: "s1", transcript_path: "/x/t.jsonl", hook_event_name: "UserPromptSubmit"}')")"
text="$(jq -r .text <<<"$line")"
assert_lacks "anthropic key is gone"   "$line" "sk-ant-api03"
assert_lacks "password value is gone"  "$line" "hunter2"
assert_has   "the rest of the prompt stays" "$text" "ship it with "
assert_has   "  ...all of it"          "$text" " please"
assert_has   "key marker names the kind" "$text" "[REDACTED:anthropic-key]"
assert_has   "assignment marker names the key" "$text" "password=[REDACTED:password]"

redact() { jq -r .text <<<"$(cap "$D" t "$(jq -n --arg p "$1" '{prompt: $p}')")"; }
assert_eq "openai key"   "[REDACTED:openai-key]"   "$(redact 'sk-proj-abcdefghijklmnopqrstuvwx')"
assert_eq "github token" "[REDACTED:github-token]" "$(redact 'ghp_''abcdefghijklmnopqrstuvwxyz0123')"
assert_eq "aws key"      "[REDACTED:aws-key]"      "$(redact 'AKIA''ABCDEFGHIJKLMNOP')"
assert_eq "slack token"  "[REDACTED:slack-token]"  "$(redact 'xoxb''-1234567890-abcdef')"
assert_eq "jwt"          "[REDACTED:jwt]"          "$(redact 'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0In0.c2lnbmF0dXJlX2hlcmU')"
assert_eq "bearer token" "Bearer [REDACTED:bearer-token]" "$(redact 'Bearer abcdefghijklmnop1234')"
assert_eq "quoted token assignment" 'API_TOKEN: [REDACTED:api_token]' "$(redact 'API_TOKEN: "two words"')"
assert_eq "json secret"  '{"client_secret": [REDACTED:client_secret]}' "$(redact '{"client_secret": "s3cr3t"}')"
assert_eq "private key block" "a [REDACTED:private-key] b" \
    "$(redact $'a -----BEGIN RSA PRIVATE'$' KEY-----\nMIIabc\n-----END RSA PRIVATE'$' KEY----- b')"
assert_eq "an already-redacted value keeps its marker" "token=[REDACTED:github-token]" \
    "$(redact 'token=ghp_''abcdefghijklmnopqrstuvwxyz0123')"
assert_eq "plain prose is untouched" "remember the passwords talk" "$(redact 'remember the passwords talk')"

# ── shape ─────────────────────────────────────────────────────────────────────
assert_eq "only ts, source, context, session, text" "context,session,source,text,ts" "$(jq -r 'keys | join(",")' <<<"$line")"
assert_eq "source is the caller's" "claude-code" "$(jq -r .source <<<"$line")"
assert_eq "context is the cwd" "/workspace/p" "$(jq -r .context <<<"$line")"
assert_eq "session is the hook's session_id" "s1" "$(jq -r .session <<<"$line")"
S2="${TMP}/s"
for s in a a b; do cap "$S2" claude-code "$(jq -n --arg s "$s" '{prompt: "p", session_id: $s}')" >/dev/null; done
assert_eq "two prompts share a session, the third differs" "a a b" "$(jq -r .session "$S2"/*-test.jsonl | tr '\n' ' ' | sed 's/ $//')"
assert_eq "no session id is null" "null" "$(jq -r .session <<<"$(cap "$S2" t '{"prompt":"x"}')")"
before="$(cat "$D"/*-test.jsonl | wc -l)"
cap "$D" t '{"prompt":"   "}' >/dev/null
assert_eq "an empty prompt writes nothing" "$before" "$(cat "$D"/*-test.jsonl | wc -l)"
assert_eq "one file per writer, per month" "$(date -u +%Y-%m)-test.jsonl" "$(cd "$D" && ls ./*.jsonl | sed 's|^\./||')"

# ── failure ───────────────────────────────────────────────────────────────────
F="${TMP}/f"; mkdir -p "$F/$(date -u +%Y-%m)-test.jsonl"   # a directory where the file goes
CAPTURE_DIR="$F" CAPTURE_HOST=test CAPTURE_WAIT=1 bash "$CAPTURE" t <<<'{"prompt":"x"}' 2>/dev/null
assert_eq "a failed write exits 0" "0" "$?"
assert_has "...and is logged" "$(cat "$F/errors.log" 2>/dev/null)" "capture failed (t)"
CAPTURE_DIR="" bash "$CAPTURE" t <<<'{"prompt":"x"}' 2>/dev/null
assert_eq "no CAPTURE_DIR still exits 0" "0" "$?"

# ── detached ──────────────────────────────────────────────────────────────────
A="${TMP}/a"
CAPTURE_DIR="$A" CAPTURE_HOST=test bash "$CAPTURE" t <<<'{"prompt":"later"}'
for _ in $(seq 50); do [[ -s "$A/$(date -u +%Y-%m)-test.jsonl" ]] && break; sleep 0.1; done
assert_eq "the detached write lands" "later" "$(jq -r .text "$A"/*-test.jsonl 2>/dev/null)"

# ── install ───────────────────────────────────────────────────────────────────
export CLAUDE_CONFIG_DIR="${TMP}/claude"
mkdir -p "$CLAUDE_CONFIG_DIR" "${TMP}/ws"
echo '{"model":"opus","hooks":{"UserPromptSubmit":[{"hooks":[{"type":"command","command":"mine.sh"}]}],"Stop":[{"hooks":[{"type":"command","command":"stop.sh"}]}]}}' \
    > "${CLAUDE_CONFIG_DIR}/settings.json"
bash "$CAPTURE" install "${TMP}/ws" >/dev/null
bash "$CAPTURE" install "${TMP}/ws" >/dev/null
S="${CLAUDE_CONFIG_DIR}/settings.json"
assert_eq "installed once, beside the user's hook" "2" "$(jq '.hooks.UserPromptSubmit | length' "$S")"
assert_eq "other settings untouched" "opus stop.sh" "$(jq -r '"\(.model) \(.hooks.Stop[0].hooks[0].command)"' "$S")"
cmd="$(jq -r '.hooks.UserPromptSubmit[1].hooks[0].command' "$S")"
assert_has "hook writes into the workspace's .capture" "$cmd" "CAPTURE_DIR='${TMP}/ws/.capture'"
# The installed command, run as Claude Code runs it: hook JSON on stdin.
CAPTURE_WAIT=1 CAPTURE_HOST=test bash -c "$cmd" <<<'{"prompt":"via the hook","cwd":"/w"}'
assert_eq "the installed hook captures" "claude-code via the hook" \
    "$(jq -r '"\(.source) \(.text)"' "${TMP}"/ws/.capture/*-test.jsonl 2>/dev/null)"
bash "$CAPTURE" uninstall >/dev/null
assert_eq "uninstall leaves only the user's hook" "mine.sh" "$(jq -r '[.hooks.UserPromptSubmit[].hooks[].command] | join(",")' "$S")"
assert_eq "nothing written outside .capture" "ws/.capture" \
    "$(cd "$TMP" && find ws -mindepth 1 -maxdepth 1 | tr '\n' ' ' | sed 's/ $//')"
unset CLAUDE_CONFIG_DIR

# ── webhook ───────────────────────────────────────────────────────────────────
assert_eq "POST /capture queues the capture machine" "capture" \
    "$(awk '/- path: \/capture$/{f=1; next} f && /machine:/{print $2; exit}' "${REPO_DIR}/automation/decree-go-rest.yml")"
W="${TMP}/w"; mkdir -p "${W}/lib"
cp -r "${REPO_DIR}/automation/lib/capture" "${W}/lib/"
printf -- '---\nmachine: capture\n---\n{"source":"phone","text":"buy filters"}\n' > "${W}/message.md"
DECREE_MESSAGE="${W}/message.md" DECREE_LIB="${W}/lib" DECREE_DATA_SOURCE=webhook CAPTURE_DIR="${W}/cap" \
    bash "${REPO_DIR}/automation/scripts/capture.sh"
assert_eq "the posted source and text are appended" "phone buy filters" \
    "$(jq -r '"\(.source) \(.text)"' "${W}"/cap/*-automation.jsonl 2>/dev/null)"

# Self-check canary: TEST_SELFCHECK=1 forces one failure so this suite's own
# FAIL→non-zero-exit path is itself testable (src/test/run-all.sh selfcheck).
[[ "${TEST_SELFCHECK:-}" == 1 ]] && _fail "selfcheck canary (deliberate failure)"

echo ""
echo "=== Results: ${PASS} passed, ${FAIL} failed ==="
[[ $FAIL -eq 0 ]] || { printf '  - %s\n' "${FAIL_NAMES[@]}"; exit 1; }
