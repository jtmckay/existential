#!/usr/bin/env bash
# test-model-client.sh — every prompt-sending path works against a server that
# speaks only OpenAI's /v1.
#
# The model URL can name ollama or a llama.cpp server, and llama.cpp has no
# /api/* routes at all. So the stub below answers /v1/chat/completions and 404s
# everything else, and each path that sends a prompt is pointed at it:
# lib/model.sh (every decree script), hermes_chat, the newsletter's write step
# and ocr.ts. The last assertion is that nothing ever asked for /api/*, and that
# ollama_pull leaves the server alone when ollama is not enabled.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
[[ -f "${REPO_DIR}/.env.exist.shared" ]] || REPO_DIR="/repo"
LIB="${REPO_DIR}/automation/lib"
TSX="$(command -v tsx || echo /opt/decree/node_modules/.bin/tsx)"

for _t in node jq curl "$TSX"; do
    if ! command -v "$_t" >/dev/null 2>&1; then
        echo "skipped — ${_t} not available (run inside existential-adhoc)"
        exit 0
    fi
done

PASS=0; FAIL=0; FAIL_NAMES=()
_ok()   { printf '  PASS  %s\n' "$1"; PASS=$((PASS + 1)); }
_fail() { printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; FAIL=$((FAIL + 1)); FAIL_NAMES+=("$1"); }
assert_eq() { if [[ "$2" == "$3" ]]; then _ok "$1"; else _fail "$1" "expected=$2 got=$3"; fi; }
assert_contains() { if [[ "$3" == *"$2"* ]]; then _ok "$1"; else _fail "$1" "missing: $2"; fi; }

TMP="$(mktemp -d)"
STUB_PID=""
trap '[ -n "$STUB_PID" ] && kill "$STUB_PID" 2>/dev/null; rm -rf "$TMP"' EXIT

# ── The stub: /v1/chat/completions and nothing else ───────────────────────────
# Replies with the contents of $TMP/reply; logs "<METHOD> <path>" and the body.
cat > "${TMP}/stub.js" <<'EOF'
const http = require("node:http");
const fs = require("node:fs");
const dir = process.argv[2];
http.createServer((req, res) => {
  let body = "";
  req.on("data", (c) => (body += c));
  req.on("end", () => {
    fs.appendFileSync(`${dir}/requests.log`, `${req.method} ${req.url}\n`);
    fs.writeFileSync(`${dir}/last-body.json`, body);
    if (req.method === "POST" && req.url === "/v1/chat/completions") {
      const content = fs.readFileSync(`${dir}/reply`, "utf8");
      res.writeHead(200, { "Content-Type": "application/json" });
      res.end(JSON.stringify({ choices: [{ message: { role: "assistant", content } }] }));
    } else {
      res.writeHead(404);
      res.end("not found");
    }
  });
}).listen(0, "127.0.0.1", function () {
  fs.writeFileSync(`${dir}/port`, String(this.address().port));
});
EOF
printf 'stub reply' > "${TMP}/reply"
node "${TMP}/stub.js" "$TMP" &
STUB_PID=$!
for _ in $(seq 1 50); do [ -s "${TMP}/port" ] && break; sleep 0.1; done
if [ ! -s "${TMP}/port" ]; then
    _fail "stub server started"
    echo ""; echo "=== Results: ${PASS} passed, ${FAIL} failed ==="; exit 1
fi
STUB="http://127.0.0.1:$(cat "${TMP}/port")/v1"
_body() { cat "${TMP}/last-body.json"; }
_reply() { printf '%s' "$1" > "${TMP}/reply"; }

export EXIST_MODEL_URL="$STUB" EXIST_MODEL_URL_CHAT="" EXIST_MODEL_URL_EXTRACT="" \
       EXIST_MODEL_URL_EMBED="" EXIST_MODEL_URL_VISION=""
export EXIST_MODEL_CHAT="chat-model" EXIST_MODEL_VISION="vision-model"

# ── lib/model.sh ──────────────────────────────────────────────────────────────

# shellcheck source=../../../automation/lib/model.sh
. "${LIB}/model.sh"

assert_eq "model_chat gets a completion from a /v1-only server" \
    "stub reply" "$(model_chat "sys" "hello" 50)"
assert_eq "model_chat sends the role's tag as the model" \
    "chat-model" "$(_body | jq -r .model)"

assert_eq "MODEL_ROLE=vision sends the vision tag" \
    "vision-model" "$(MODEL_ROLE=vision model_chat s u >/dev/null; _body | jq -r .model)"

assert_eq "MODEL_NAME set but empty sends no model" \
    "absent" "$(MODEL_NAME="" model_chat s u >/dev/null; _body | jq -r '.model // "absent"')"

_reply "YES: it is about boats"
_reason="$(model_gate "boats" "a note about boats")"; _rc=$?
assert_eq "model_gate YES returns 0" "0" "$_rc"
assert_eq "model_gate YES gives the reason" "it is about boats" "$_reason"
_reply "NO"
model_gate "boats" "a grocery list" >/dev/null; assert_eq "model_gate NO returns 1" "1" "$?"
EXIST_MODEL_URL="http://127.0.0.1:9/v1" model_gate "boats" "x" >/dev/null 2>&1
assert_eq "model_gate with no server returns 2 (no verdict)" "2" "$?"
_reply "stub reply"

# hermes_chat is model_chat aimed at the gateway, so the same request shape.
# shellcheck source=../../../automation/lib/hermes.sh
. "${LIB}/hermes.sh"
assert_eq "hermes_chat reaches the same /v1 shape" \
    "stub reply" "$(HERMES_API_URL="$STUB" HERMES_API_KEY=k hermes_chat s u 10)"
assert_eq "hermes_chat with no HERMES_MODEL lets the gateway choose" \
    "absent" "$(_body | jq -r '.model // "absent"')"

# ── The newsletter's write step ───────────────────────────────────────────────

mkdir -p "${TMP}/run"
printf '{"title":"t","link":"https://example.test/a"}\n' > "${TMP}/run/items.jsonl"
_reply "- [t](https://example.test/a): worth it"
if DECREE_RUN_DIR="${TMP}/run" DECREE_LIB="$LIB" bash "${REPO_DIR}/automation/scripts/newsletter/write.sh" >/dev/null 2>"${TMP}/write.err"; then
    assert_contains "newsletter write gets a completion" \
        "worth it" "$(cat "${TMP}/run/issue.md")"
else
    _fail "newsletter write gets a completion" "$(cat "${TMP}/write.err")"
fi

# ── OCR ───────────────────────────────────────────────────────────────────────

# A 1x1 PNG.
printf '%s' 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==' \
    | base64 -d > "${TMP}/pixel.png"
_reply "RECEIPT TOTAL 4.20"
_ocr="$(FILE_PATH="${TMP}/pixel.png" MODEL_URL="$(model_url vision)" \
        "$TSX" "${LIB}/ocr.ts" 2>"${TMP}/ocr.err")"
assert_eq "ocr.ts gets a completion from a /v1-only server" "RECEIPT TOTAL 4.20" "$_ocr"
assert_eq "ocr.ts sends the image as a data URI" \
    "data:image/png;base64," "$(_body | jq -r '.messages[0].content[] | select(.type=="image_url") | .image_url.url' | cut -c1-22)"
assert_eq "ocr.ts sends the vision tag" "vision-model" "$(_body | jq -r .model)"

# ── ollama-only steps stay away when ollama is off ────────────────────────────

_before="$(wc -l < "${TMP}/requests.log")"
_out="$(EXIST_IS_AI_OLLAMA=false DECREE_LIB="$LIB" timeout 20 bash "${REPO_DIR}/automation/scripts/ollama_pull.sh" 2>&1)"; _rc=$?
assert_eq "ollama_pull is a clean no-op without ollama" "0" "$_rc"
assert_eq "ollama_pull sent nothing to the server" "$_before" "$(wc -l < "${TMP}/requests.log")"

if grep -q ' /api/' "${TMP}/requests.log"; then
    _fail "no path asked for ollama's /api/*" "$(grep ' /api/' "${TMP}/requests.log" | sort -u | tr '\n' ' ')"
else
    _ok "no path asked for ollama's /api/*"
fi

# Self-check canary: TEST_SELFCHECK=1 forces one failure so this suite's own
# FAIL→non-zero-exit path is itself testable (src/test/run-all.sh selfcheck).
[[ "${TEST_SELFCHECK:-}" == 1 ]] && _fail "selfcheck canary (deliberate failure)"

echo ""
echo "=== Results: ${PASS} passed, ${FAIL} failed ==="
if [ "$FAIL" -gt 0 ]; then
    printf 'Failed: %s\n' "${FAIL_NAMES[*]}"
    exit 1
fi
