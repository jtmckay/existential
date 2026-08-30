#!/usr/bin/env bash
# test-model-endpoints.sh — per-role model endpoints and their fallback.
#
# Splitting model roles across machines is a silent-failure feature: point the
# embed role at a box with no embedding model and nothing errors at startup —
# openviking just indexes into a vector store built on garbage, and you find out
# when search returns nonsense weeks later. The fallback is the same shape: a
# blank per-role key must mean "wherever EXIST_OLLAMA_URL points", because every
# install that predates roles has all four blank.
#
# So the assertions are about the contract between the three places that resolve
# a role, which must never disagree:
#   src/utils/model-endpoints.sh  — scripts (hermes, openviking, models.sh)
#   src/templates.sh              — rendered configs (honcho's config.toml)
#   automations/shared_routines/ollama-pull.sh — migrations, which pull the model
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
[[ -f "${SRC_DIR}/quest.sh" ]] || SRC_DIR="/src"

REPO_DIR="$(cd "${SRC_DIR}/.." && pwd)"
[[ -f "${REPO_DIR}/.env.exist.shared" ]] || REPO_DIR="/repo"

ENDPOINTS="${SRC_DIR}/utils/model-endpoints.sh"
TEMPLATES="${SRC_DIR}/templates.sh"
SHIPPED="${REPO_DIR}/.env.exist.shared"
PULL="${REPO_DIR}/automations/shared_routines/ollama-pull.sh"
HONCHO="${REPO_DIR}/ai/honcho/config.exist.toml"

# Speech has no endpoint keys on purpose — wyoming-whisper and wyoming-piper are
# CPU-only, so there is no VRAM to spread and nothing here to assert.

PASS=0; FAIL=0; FAIL_NAMES=()
_ok()   { printf '  PASS  %s\n' "$1"; PASS=$((PASS + 1)); }
_fail() { printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; FAIL=$((FAIL + 1)); FAIL_NAMES+=("$1"); }

ROLES="chat extract embed vision"

# ── The resolver ──────────────────────────────────────────────────────────────

# shellcheck source=/dev/null
. "$ENDPOINTS"

# Blank role key → the global. This is the single-box path every existing
# install is on, so it is the one that must never regress.
(
    export EXIST_OLLAMA_URL="http://global:11434"
    export EXIST_OLLAMA_URL_CHAT="" EXIST_OLLAMA_URL_EXTRACT="" \
           EXIST_OLLAMA_URL_EMBED="" EXIST_OLLAMA_URL_VISION=""
    _bad=""
    for _r in $ROLES; do
        [[ "$(endpoint_for "$_r")" == "http://global:11434" ]] || _bad+="${_r} "
    done
    [[ -z "$_bad" ]] || { echo "$_bad"; exit 1; }
) >/dev/null 2>&1 \
    && _ok "a blank role key falls back to EXIST_OLLAMA_URL" \
    || _fail "a blank role key falls back to EXIST_OLLAMA_URL" "some role did not fall back"

# A set role key wins, and does NOT leak into its neighbours.
(
    export EXIST_OLLAMA_URL="http://global:11434"
    export EXIST_OLLAMA_URL_CHAT="" EXIST_OLLAMA_URL_EXTRACT="" \
           EXIST_OLLAMA_URL_VISION=""
    export EXIST_OLLAMA_URL_EMBED="http://embedbox:11434"
    [[ "$(endpoint_for embed)"   == "http://embedbox:11434" ]] || exit 1
    [[ "$(endpoint_for chat)"    == "http://global:11434"   ]] || exit 1
    [[ "$(endpoint_for extract)" == "http://global:11434"   ]] || exit 1
    [[ "$(endpoint_for vision)"  == "http://global:11434"   ]] || exit 1
) >/dev/null 2>&1 \
    && _ok "a set role key wins and does not leak to other roles" \
    || _fail "a set role key wins and does not leak to other roles"

# chat-ctx is ollama-pull's rebuild role; it must land on the chat machine or the
# rebuilt model appears on a box that never serves chat.
(
    export EXIST_OLLAMA_URL="http://global:11434"
    export EXIST_OLLAMA_URL_CHAT="http://chatbox:11434"
    [[ "$(endpoint_for chat-ctx)" == "http://chatbox:11434" ]]
) >/dev/null 2>&1 \
    && _ok "chat-ctx resolves to the chat endpoint" \
    || _fail "chat-ctx resolves to the chat endpoint"

# An unknown role must fail loudly. Returning the default instead would send a
# typo's traffic to the wrong machine with no error anywhere.
( endpoint_for definitely-not-a-role ) >/dev/null 2>&1 \
    && _fail "an unknown role fails instead of defaulting" "endpoint_for returned success" \
    || _ok "an unknown role fails instead of defaulting"

# endpoints_are_uniform is what models.sh keys its advice off.
(
    export EXIST_OLLAMA_URL="http://global:11434"
    export EXIST_OLLAMA_URL_CHAT="" EXIST_OLLAMA_URL_EXTRACT="" \
           EXIST_OLLAMA_URL_EMBED="" EXIST_OLLAMA_URL_VISION=""
    endpoints_are_uniform
) >/dev/null 2>&1 \
    && _ok "endpoints_are_uniform is true on a single-box install" \
    || _fail "endpoints_are_uniform is true on a single-box install"

(
    export EXIST_OLLAMA_URL="http://global:11434"
    export EXIST_OLLAMA_URL_CHAT="" EXIST_OLLAMA_URL_EXTRACT="" \
           EXIST_OLLAMA_URL_VISION=""
    export EXIST_OLLAMA_URL_EMBED="http://embedbox:11434"
    endpoints_are_uniform
) >/dev/null 2>&1 \
    && _fail "endpoints_are_uniform is false once a role is moved" \
    || _ok "endpoints_are_uniform is false once a role is moved"

# ── The three resolvers agree on the role list ────────────────────────────────

_missing=""
for _r in $ROLES; do
    _key="EXIST_OLLAMA_URL_$(printf '%s' "$_r" | tr '[:lower:]' '[:upper:]')"
    grep -qE "^${_key}=" "$SHIPPED"       || _missing+="${_key}(.env.exist.shared) "
    grep -q  "$_key"     "$ENDPOINTS"     || _missing+="${_key}(model-endpoints.sh) "
    grep -q  "$_key"     "$PULL"          || _missing+="${_key}(ollama-pull.sh) "
done
[[ -z "$_missing" ]] \
    && _ok "every role has a key in the shipped env, the resolver and ollama-pull" \
    || _fail "every role has a key in the shipped env, the resolver and ollama-pull" "missing: $_missing"

# templates.sh resolves the blanks for rendered configs. Its loop is a literal
# list of role names, so it is the one place that silently omits a new role.
_tmpl_missing=""
for _r in CHAT EXTRACT EMBED VISION; do
    grep -qE "for _role in .*${_r}" "$TEMPLATES" || _tmpl_missing+="${_r} "
done
[[ -z "$_tmpl_missing" ]] \
    && _ok "templates.sh resolves every role's blank at render time" \
    || _fail "templates.sh resolves every role's blank at render time" "missing: $_tmpl_missing"

# ── Every role has BOTH halves ────────────────────────────────────────────────
#
# A role is "which model" AND "on which machine". Adding one without the other is
# the silent gap: a new role with an endpoint but no EXIST_MODEL_* resolves to an
# empty tag and ollama-pull skips it (that is how a blank VISION disables images),
# so nothing errors — the model simply never gets pulled and every call 404s at
# runtime. Assert the pair, not each half.
_unpaired=""
for _r in CHAT EXTRACT EMBED VISION; do
    grep -qE "^EXIST_MODEL_${_r}="      "$SHIPPED" || _unpaired+="${_r}(no model) "
    grep -qE "^EXIST_OLLAMA_URL_${_r}=" "$SHIPPED" || _unpaired+="${_r}(no endpoint) "
done
[[ -z "$_unpaired" ]] \
    && _ok "every role has both a model tag and an endpoint" \
    || _fail "every role has both a model tag and an endpoint" "unpaired: $_unpaired"

# The two role-scoped extras. Neither is a tag or an address, but both belong to
# exactly one role and break that role alone when wrong: a stale num_ctx makes
# hermes overflow silently, a mismatched dim corrupts the vector index.
grep -qE "^EXIST_MODEL_CHAT_NUM_CTX=" "$SHIPPED" \
    && _ok "the chat role carries its context window" \
    || _fail "the chat role carries its context window"

grep -qE "^EXIST_MODEL_EMBED_DIM=" "$SHIPPED" \
    && _ok "the embed role carries its vector dimensions" \
    || _fail "the embed role carries its vector dimensions"

# ── The shipped env ships them blank ──────────────────────────────────────────
#
# A shipped value would quietly pin every new install to one machine and make
# EXIST_OLLAMA_URL a setting that does nothing.
_nonblank=""
for _r in CHAT EXTRACT EMBED VISION; do
    _v=$(grep -E "^EXIST_OLLAMA_URL_${_r}=" "$SHIPPED" | head -1 | cut -d= -f2-)
    [[ -z "$_v" ]] || _nonblank+="${_r}=${_v} "
done
[[ -z "$_nonblank" ]] \
    && _ok ".env.exist.shared ships every role endpoint blank" \
    || _fail ".env.exist.shared ships every role endpoint blank" "set: $_nonblank"

# ── honcho actually uses the roles ────────────────────────────────────────────
#
# honcho is the only consumer that talks to TWO roles, so a regression there is
# the one that reintroduces a single hardcoded address for the whole stack.
grep -q 'EXIST_OLLAMA_URL_EMBED/v1' "$HONCHO" \
    && _ok "honcho's embedding block uses the embed endpoint" \
    || _fail "honcho's embedding block uses the embed endpoint"

grep -q 'EXIST_OLLAMA_URL_EXTRACT/v1' "$HONCHO" \
    && _ok "honcho's deriver/dialectic blocks use the extract endpoint" \
    || _fail "honcho's deriver/dialectic blocks use the extract endpoint"

grep -q '"EXIST_OLLAMA_URL/v1"' "$HONCHO" \
    && _fail "honcho names no bare EXIST_OLLAMA_URL endpoint" "a base_url still uses the global directly" \
    || _ok "honcho names no bare EXIST_OLLAMA_URL endpoint"

# ── Summary ───────────────────────────────────────────────────────────────────

echo ""
echo "=== Results: ${PASS} passed, ${FAIL} failed ==="
if [ "$FAIL" -gt 0 ]; then
    printf 'Failed: %s\n' "${FAIL_NAMES[*]}"
    exit 1
fi
