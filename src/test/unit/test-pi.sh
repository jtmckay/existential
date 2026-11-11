#!/usr/bin/env bash
# test-pi.sh — the pi plugin's lib/pi.sh: what pi is configured with, and what one
# run in a department is allowed to reach.
#
#   configure  the "existential" provider is the chat role's URL and tag; an MCP
#              server is registered only while its add-on is on; a provider or
#              server someone added survives; telemetry is off.
#   run        a department's tools and MCP servers become pi's --tools list,
#              no MCP means --no-mcp, no tools means --no-tools, and no
#              department passes neither. `pi` is a stub that prints its argv.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
[[ -f "${REPO_DIR}/.env.exist.shared" ]] || REPO_DIR="/repo"

PASS=0; FAIL=0; FAIL_NAMES=()
_ok()   { printf '  PASS  %s\n' "$1"; PASS=$((PASS + 1)); }
_fail() { printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; FAIL=$((FAIL + 1)); FAIL_NAMES+=("$1"); }
assert_eq() { if [[ "$2" == "$3" ]]; then _ok "$1"; else _fail "$1" "expected=$2 got=$3"; fi; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

export EXIST_MODEL_URL="http://ollama:11434/v1" EXIST_MODEL_URL_CHAT="http://chatbox:11434/v1"
export EXIST_MODEL_CHAT="gemma4:e2b-it-qat" EXIST_MODEL_CHAT_NUM_CTX=65536
export PI_CODING_AGENT_DIR="${TMP}/agent"
( source "${REPO_DIR}/automation/lib/automations/registry.sh"; source "${REPO_DIR}/automation/lib/automations/plugin.sh"; plugin_unpack pi "${TMP}/unpacked" ) >/dev/null
# shellcheck source=/dev/null
. "${TMP}/unpacked/.decree/lib/pi.sh"

# ── configure ─────────────────────────────────────────────────────────────────
mkdir -p "$PI_CODING_AGENT_DIR"
echo '{"providers":{"mine":{"baseUrl":"https://x"}},"x":1}' > "${PI_CODING_AGENT_DIR}/models.json"
echo '{"mcpServers":{"mine":{"url":"https://y"},"firecrawl":{"url":"stale"}}}' > "${PI_CODING_AGENT_DIR}/mcp.json"
OPENVIKING_API_KEY=k EXIST_IS_AI_FIRECRAWL=false EXIST_IS_AI_MCP=true EXIST_IS_AI_QMD=false pi_configure
M="${PI_CODING_AGENT_DIR}/models.json"; S="${PI_CODING_AGENT_DIR}/mcp.json"; C="${PI_CODING_AGENT_DIR}/settings.json"

assert_eq "provider baseUrl is the chat role's URL" "http://chatbox:11434/v1" "$(jq -r .providers.existential.baseUrl "$M")"
assert_eq "provider speaks openai-completions" "openai-completions" "$(jq -r .providers.existential.api "$M")"
assert_eq "provider declares the chat tag" "gemma4:e2b-it-qat" "$(jq -r '.providers.existential.models[0].id' "$M")"
assert_eq "provider carries the chat context" "65536" "$(jq -r '.providers.existential.models[0].contextWindow' "$M")"
assert_eq "a provider someone added survives" "https://x" "$(jq -r .providers.mine.baseUrl "$M")"
assert_eq "MCP servers: on add-ons only, theirs kept" "mine,openviking,playwright" \
    "$(jq -r '.mcpServers | keys | join(",")' "$S")"
assert_eq "openviking's key stays in the environment" 'Bearer ${OPENVIKING_API_KEY}' \
    "$(jq -r .mcpServers.openviking.headers.Authorization "$S")"
assert_eq "our servers are declared directly" "direct" "$(jq -r .mcpServers.playwright.exposure "$S")"
assert_eq "install telemetry is off" "false" "$(jq -r .enableInstallTelemetry "$C")"
assert_eq "a bare pi starts on the stack's model" "existential/gemma4:e2b-it-qat" \
    "$(jq -r '.defaultProvider + "/" + .defaultModel' "$C")"

# ── run ───────────────────────────────────────────────────────────────────────
mkdir -p "${TMP}/bin" "${TMP}/depts" "${TMP}/ws"
printf '#!/bin/sh\nfor a; do printf "%%s\\n" "$a"; done\n' > "${TMP}/bin/pi"
chmod +x "${TMP}/bin/pi"
printf 'description: d\ntools: read, grep\nmcp: openviking, firecrawl\n' > "${TMP}/depts/research.yml"
printf 'description: d\ntools: read\nmcp:\n' > "${TMP}/depts/offline.yml"
printf 'description: d\ntools:\nmcp:\n' > "${TMP}/depts/bare.yml"
_args() { PATH="${TMP}/bin:$PATH" PI_DEPARTMENTS="${TMP}/depts" AUTOMATIONS_WORKSPACE="${TMP}/ws" \
    pi_run "$1" sys prompt | tr '\n' ' '; }

case "$(_args research)" in
    *"--tools read,grep,mcp__openviking__*,mcp__firecrawl__*"*) _ok "a department's tools and servers are its --tools" ;;
    *) _fail "a department's tools and servers are its --tools" "$(_args research)" ;;
esac
case "$(_args offline)" in
    *"--tools read --no-mcp"*) _ok "a department with no server runs --no-mcp" ;;
    *) _fail "a department with no server runs --no-mcp" "$(_args offline)" ;;
esac
case "$(_args bare)" in
    *"--no-tools --no-mcp"*) _ok "a department with nothing runs --no-tools --no-mcp" ;;
    *) _fail "a department with nothing runs --no-tools --no-mcp" "$(_args bare)" ;;
esac
case "$(_args "")" in
    *--tools*|*--no-mcp*|*--no-tools*) _fail "no department keeps pi's defaults" "$(_args "")" ;;
    *"--model gemma4:e2b-it-qat"*) _ok "no department keeps pi's defaults" ;;
    *) _fail "no department keeps pi's defaults" "$(_args "")" ;;
esac
[[ -z "$(_args nosuch 2>/dev/null)" ]] && _ok "an unknown department runs nothing" \
    || _fail "an unknown department runs nothing" "pi was called"
for _d in "${TMP}"/unpacked/.decree/lib/departments/*.yml; do
    grep -q '^description: .' "$_d" && _ok "$(basename "$_d") has a description" \
        || _fail "$(basename "$_d") has a description"
done

[[ "${TEST_SELFCHECK:-}" == 1 ]] && _fail "selfcheck canary (deliberate failure)"

echo ""
echo "=== Results: ${PASS} passed, ${FAIL} failed ==="
if [ "$FAIL" -gt 0 ]; then
    printf 'Failed: %s\n' "${FAIL_NAMES[*]}"
    exit 1
fi
