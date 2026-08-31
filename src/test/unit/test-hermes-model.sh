#!/usr/bin/env bash
# test-hermes-model.sh — which hermes model: blocks are ours to reconcile.
#
# "Model choice is global, never per-service" (CLAUDE.md): EXIST_MODEL_CHAT is
# named once and every consumer follows it. hermes is the one consumer that keeps
# its own copy, in config.yaml, so it has to be reconciled — and getting the
# boundary wrong fails silently in both directions:
#
#   too narrow  → changing EXIST_MODEL_CHAT moves everything except the agent,
#                 which keeps answering from the first model it was ever given
#   too wide    → a user who pointed hermes at Anthropic finds their choice
#                 overwritten on the next render
#
# The boundary is "does this still look like something existential set": provider
# "custom" plus a host:11434 endpoint, the same test openviking applies to
# ov.conf's api_base. Note it matches ANY :11434 host rather than the configured
# one — otherwise moving the chat role to another box would read as a deliberate
# choice and freeze the config at the dead address.
#
# exist.initial.sh cannot be sourced (its top level runs docker create/cp), so the
# helpers are extracted by name, the way test-existential.sh sources only the top
# half of existential.sh. Read-only; runs anywhere with bash and awk.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
[[ -f "${REPO_DIR}/.env.exist.shared" ]] || REPO_DIR="/repo"
INIT="${REPO_DIR}/ai/hermes/exist.initial.sh"

if [[ ! -f "$INIT" ]]; then
    echo "skipped — ${INIT} not found"
    exit 0
fi

PASS=0; FAIL=0; FAIL_NAMES=()
_ok()   { printf '  PASS  %s\n' "$1"; PASS=$((PASS + 1)); }
_fail() { printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; FAIL=$((FAIL + 1)); FAIL_NAMES+=("$1"); }
assert_eq() { if [[ "$2" == "$3" ]]; then _ok "$1"; else _fail "$1" "expected=$2 got=$3"; fi; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Pull just the four model: helpers out of the init script.
awk '/^_hermes_model_block\(\)|^_hermes_model_field\(\)|^_hermes_model_is_ours\(\)|^_hermes_write_model_block\(\)/{f=1}
     f{print} f&&/^}$/{f=0}' "$INIT" > "${TMP}/fns.sh"

_n_fns=$(grep -c '^_hermes.*() {' "${TMP}/fns.sh")
assert_eq "extracted all four model helpers" "4" "$_n_fns"
if [[ "$_n_fns" != "4" ]]; then
    echo "  (a helper was renamed — update the awk pattern above)" >&2
    echo ""; echo "=== Results: ${PASS} passed, ${FAIL} failed ==="; exit 1
fi

# shellcheck disable=SC1091  # generated above
. "${TMP}/fns.sh"

_cfg() { printf '%s\n' "$2" > "${TMP}/$1"; printf '%s' "${TMP}/$1"; }

# ── Ours: provider custom + an ollama endpoint ────────────────────────────────

OURS="$(_cfg ours.yaml 'mcp_servers:
  openviking:
model:
  default: "stale-model:7b"
  provider: "custom"
  base_url: "http://taylors4:11434/v1"
  context_length: 32768
trailing: keep-me')"

assert_eq "reads default from the block" "stale-model:7b"           "$(_hermes_model_field "$OURS" default)"
assert_eq "reads base_url from the block" "http://taylors4:11434/v1" "$(_hermes_model_field "$OURS" base_url)"
_hermes_model_is_ours "$OURS"; assert_eq "an ollama block is ours" "0" "$?"

# ── Not ours: a deliberate provider choice ────────────────────────────────────

ANTHROPIC="$(_cfg anthropic.yaml 'model:
  default: "claude-opus-4"
  provider: "anthropic"
  base_url: "https://api.anthropic.com/v1"
  context_length: 200000')"
_hermes_model_is_ours "$ANTHROPIC"; assert_eq "an anthropic block is NOT ours" "1" "$?"

# provider custom is not enough on its own — the endpoint has to be ollama's.
OPENROUTER="$(_cfg openrouter.yaml 'model:
  default: "meta/llama"
  provider: "custom"
  base_url: "https://openrouter.ai/api/v1"
  context_length: 65536')"
_hermes_model_is_ours "$OPENROUTER"; assert_eq "custom + non-ollama endpoint is NOT ours" "1" "$?"

# ── Regression: ollama that MOVED is still ours ───────────────────────────────
# Matching only the currently-configured URL would strand the config at whatever
# address it had when the box went away.

MOVED="$(_cfg moved.yaml 'model:
  default: "m"
  provider: "custom"
  base_url: "http://retired-box:11434/v1"
  context_length: 65536')"
_hermes_model_is_ours "$MOVED"; assert_eq "ollama on a different host is still ours" "0" "$?"

# ── The rewrite itself ────────────────────────────────────────────────────────

_hermes_write_model_block "$OURS" "gemma4-128k" 65536 "http://newbox:11434"
assert_eq "default reconciled"        "gemma4-128k"            "$(_hermes_model_field "$OURS" default)"
assert_eq "base_url reconciled"       "http://newbox:11434/v1" "$(_hermes_model_field "$OURS" base_url)"
assert_eq "context_length reconciled" "65536"                  "$(_hermes_model_field "$OURS" context_length)"
assert_eq "provider still custom"     "custom"                 "$(_hermes_model_field "$OURS" provider)"

# Everything outside the model: block must survive — mcp_servers in particular,
# since hermes' tools live there and rewriting the file would silently disarm it.
assert_eq "content above the block survives" "  openviking:"  "$(grep 'openviking:' "$OURS")"
assert_eq "content below the block survives" "trailing: keep-me" "$(grep '^trailing:' "$OURS")"

# Reconciling twice must not stack duplicate keys.
_hermes_write_model_block "$OURS" "gemma4-128k" 65536 "http://newbox:11434"
assert_eq "no duplicate default: after a second pass" "1" "$(_hermes_model_block "$OURS" | grep -c 'default:')"

# Self-check canary: TEST_SELFCHECK=1 forces one failure so this suite's own
# FAIL→non-zero-exit path is itself testable (src/test/run-all.sh selfcheck).
[[ "${TEST_SELFCHECK:-}" == 1 ]] && _fail "selfcheck canary (deliberate failure)"

echo ""
echo "=== Results: ${PASS} passed, ${FAIL} failed ==="
if [ "$FAIL" -gt 0 ]; then
    printf 'Failed: %s\n' "${FAIL_NAMES[*]}"
    exit 1
fi
