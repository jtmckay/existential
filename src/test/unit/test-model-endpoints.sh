#!/usr/bin/env bash
# test-model-endpoints.sh — per-role model endpoints and their fallback.
#
# Splitting model roles across machines is a silent-failure feature: point the
# embed role at a box with no embedding model and nothing errors at startup —
# openviking just indexes into a vector store built on garbage, and you find out
# when search returns nonsense weeks later. The fallback is the same shape: a
# blank per-role key must mean "wherever EXIST_MODEL_URL points", because that is
# how every single-box install runs.
#
# So the assertions are about the contract between the three places that resolve
# a role, which must never disagree:
#   src/utils/model-endpoints.sh  — host scripts (hermes, openviking, models.sh)
#   src/templates.sh              — rendered configs (honcho's config.toml)
#   automation/lib/model.sh       — inside the decree container, which cannot see src/
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
[[ -f "${SRC_DIR}/quest.sh" ]] || SRC_DIR="/src"

REPO_DIR="$(cd "${SRC_DIR}/.." && pwd)"
[[ -f "${REPO_DIR}/.env.exist.shared" ]] || REPO_DIR="/repo"

ENDPOINTS="${SRC_DIR}/utils/model-endpoints.sh"
TEMPLATES="${SRC_DIR}/templates.sh"
SHIPPED="${REPO_DIR}/.env.exist.shared"
MODEL_LIB="${REPO_DIR}/automation/lib/model.sh"
HONCHO="${REPO_DIR}/ai/honcho/config.exist.toml"
DEFAULT_URL="http://ollama:11434/v1"

# Speech has no endpoint keys on purpose — wyoming-whisper and wyoming-piper are
# CPU-only, so there is no VRAM to spread and nothing here to assert.

PASS=0; FAIL=0; FAIL_NAMES=()
_ok()   { printf '  PASS  %s\n' "$1"; PASS=$((PASS + 1)); }
_fail() { printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; FAIL=$((FAIL + 1)); FAIL_NAMES+=("$1"); }

ROLES="chat extract embed vision"
_blank_roles() {
    export EXIST_MODEL_URL_CHAT="" EXIST_MODEL_URL_EXTRACT="" \
           EXIST_MODEL_URL_EMBED="" EXIST_MODEL_URL_VISION=""
}

# ── The resolver ──────────────────────────────────────────────────────────────

# shellcheck source=/dev/null
. "$ENDPOINTS"
# shellcheck source=/dev/null
. "$MODEL_LIB"

# Blank role key → the global. This is the single-box path, so it is the one
# that must never regress.
(
    export EXIST_MODEL_URL="http://global:8080/v1"; _blank_roles
    _bad=""
    for _r in $ROLES; do
        [[ "$(endpoint_for "$_r")" == "http://global:8080/v1" ]] || _bad+="${_r} "
    done
    [[ -z "$_bad" ]] || { echo "$_bad"; exit 1; }
) >/dev/null 2>&1 \
    && _ok "a blank role key falls back to EXIST_MODEL_URL" \
    || _fail "a blank role key falls back to EXIST_MODEL_URL" "some role did not fall back"

# A set role key wins, and does NOT leak into its neighbours.
(
    export EXIST_MODEL_URL="http://global:8080/v1"; _blank_roles
    export EXIST_MODEL_URL_EMBED="http://embedbox:11434/v1"
    [[ "$(endpoint_for embed)"   == "http://embedbox:11434/v1" ]] || exit 1
    [[ "$(endpoint_for chat)"    == "http://global:8080/v1"    ]] || exit 1
    [[ "$(endpoint_for extract)" == "http://global:8080/v1"    ]] || exit 1
    [[ "$(endpoint_for vision)"  == "http://global:8080/v1"    ]] || exit 1
) >/dev/null 2>&1 \
    && _ok "a set role key wins and does not leak to other roles" \
    || _fail "a set role key wins and does not leak to other roles"

# chat-ctx is ollama_pull's rebuild role; it must land on the chat machine or the
# rebuilt model appears on a box that never serves chat.
(
    export EXIST_MODEL_URL="http://global:8080/v1"
    export EXIST_MODEL_URL_CHAT="http://chatbox:11434/v1"
    [[ "$(endpoint_for chat-ctx)" == "http://chatbox:11434/v1" ]]
) >/dev/null 2>&1 \
    && _ok "chat-ctx resolves to the chat endpoint" \
    || _fail "chat-ctx resolves to the chat endpoint"

# Nothing set at all → the local ollama's /v1.
(
    unset EXIST_MODEL_URL; _blank_roles
    [[ "$(endpoint_for chat)" == "$DEFAULT_URL" ]]
) >/dev/null 2>&1 \
    && _ok "with nothing set, every role is the local ollama's /v1" \
    || _fail "with nothing set, every role is the local ollama's /v1"

# An unknown role must fail loudly. Returning the default instead would send a
# typo's traffic to the wrong machine with no error anywhere.
( endpoint_for definitely-not-a-role ) >/dev/null 2>&1 \
    && _fail "an unknown role fails instead of defaulting" "endpoint_for returned success" \
    || _ok "an unknown role fails instead of defaulting"

# ollama's own API lives at the root, not under /v1.
(
    export EXIST_MODEL_URL="http://ollama:11434/v1"; _blank_roles
    [[ "$(ollama_root_for chat)" == "http://ollama:11434" ]]
) >/dev/null 2>&1 \
    && _ok "ollama_root_for strips /v1" \
    || _fail "ollama_root_for strips /v1"

# endpoints_are_uniform is what models.sh keys its advice off.
(
    export EXIST_MODEL_URL="http://global:8080/v1"; _blank_roles
    endpoints_are_uniform
) >/dev/null 2>&1 \
    && _ok "endpoints_are_uniform is true on a single-box install" \
    || _fail "endpoints_are_uniform is true on a single-box install"

(
    export EXIST_MODEL_URL="http://global:8080/v1"; _blank_roles
    export EXIST_MODEL_URL_EMBED="http://embedbox:11434/v1"
    endpoints_are_uniform
) >/dev/null 2>&1 \
    && _fail "endpoints_are_uniform is false once a role is moved" \
    || _ok "endpoints_are_uniform is false once a role is moved"

# ── The three resolvers agree ─────────────────────────────────────────────────

# The container's copy, compared by behaviour rather than by grep: every role,
# under a blank install, a split one, and one with nothing set at all.
_disagree=""
for _case in "global" "split" "unset"; do
    for _r in $ROLES chat-ctx; do
        _a="$(
            _blank_roles
            case "$_case" in
                global) export EXIST_MODEL_URL="http://g:1/v1" ;;
                split)  export EXIST_MODEL_URL="http://g:1/v1" EXIST_MODEL_URL_CHAT="http://c:2/v1" \
                               EXIST_MODEL_URL_EXTRACT="http://x:3/v1" EXIST_MODEL_URL_EMBED="http://e:4/v1" \
                               EXIST_MODEL_URL_VISION="http://v:5/v1" ;;
                unset)  unset EXIST_MODEL_URL ;;
            esac
            printf '%s|%s' "$(endpoint_for "$_r")" "$(model_url "$_r")"
        )"
        [[ "${_a%%|*}" == "${_a#*|}" ]] || _disagree+="${_case}/${_r}(${_a}) "
    done
done
( model_url definitely-not-a-role ) >/dev/null 2>&1 && _disagree+="unknown-role-accepted "
[[ -z "$_disagree" ]] \
    && _ok "automation/lib/model.sh resolves every role exactly as model-endpoints.sh" \
    || _fail "automation/lib/model.sh resolves every role exactly as model-endpoints.sh" "$_disagree"

# templates.sh resolves the blanks for rendered configs. Its loop is a literal
# list of role names, so it is the one place that silently omits a new role.
_tmpl_missing=""
for _r in CHAT EXTRACT EMBED VISION; do
    grep -qE "for _role in .*${_r}" "$TEMPLATES" || _tmpl_missing+="${_r} "
done
[[ -z "$_tmpl_missing" ]] \
    && _ok "templates.sh resolves every role's blank at render time" \
    || _fail "templates.sh resolves every role's blank at render time" "missing: $_tmpl_missing"

# One default, everywhere it is written.
_default_off=""
grep -qE "^EXIST_MODEL_URL=${DEFAULT_URL}$" "$SHIPPED" || _default_off+=".env.exist.shared "
grep -qF "\${_vals[EXIST_MODEL_URL]:-${DEFAULT_URL}}" "$TEMPLATES" || _default_off+="templates.sh "
[[ -z "$_default_off" ]] \
    && _ok "the shipped default and templates.sh agree on ${DEFAULT_URL}" \
    || _fail "the shipped default and templates.sh agree on ${DEFAULT_URL}" "off: $_default_off"

# ── The shipped env ───────────────────────────────────────────────────────────

_missing=""
for _r in CHAT EXTRACT EMBED VISION; do
    grep -qE "^EXIST_MODEL_URL_${_r}=" "$SHIPPED" || _missing+="EXIST_MODEL_URL_${_r} "
done
[[ -z "$_missing" ]] \
    && _ok "every role has an endpoint key in the shipped env" \
    || _fail "every role has an endpoint key in the shipped env" "missing: $_missing"

# The address is OpenAI-compatible, whatever serves it — the block that holds it
# must not read as ollama's. Values are exempt: the default host IS the ollama
# container.
_block="$(sed -n '/Model Endpoints/,/^EXIST_MODEL_URL_VISION=/p' "$SHIPPED")"
_named="$(printf '%s\n' "$_block" | sed 's/=.*//' | grep -in 'ollama' || true)"
[[ -z "$_named" ]] \
    && _ok "the Model Endpoints keys and comments do not name ollama" \
    || _fail "the Model Endpoints keys and comments do not name ollama" "$_named"

grep -qE '^EXIST_OLLAMA_URL' "$SHIPPED" \
    && _fail "no EXIST_OLLAMA_URL* key is shipped" \
    || _ok "no EXIST_OLLAMA_URL* key is shipped"

# ── Every role has BOTH halves ────────────────────────────────────────────────
#
# A role is "which model" AND "on which machine". Adding one without the other is
# the silent gap: a new role with an endpoint but no EXIST_MODEL_* resolves to an
# empty tag, so nothing errors — the model simply never gets loaded and every
# call 404s at runtime. Assert the pair, not each half.
_unpaired=""
for _r in CHAT EXTRACT EMBED VISION; do
    grep -qE "^EXIST_MODEL_${_r}="     "$SHIPPED" || _unpaired+="${_r}(no model) "
    grep -qE "^EXIST_MODEL_URL_${_r}=" "$SHIPPED" || _unpaired+="${_r}(no endpoint) "
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

# A shipped role value would quietly pin every new install to one machine and
# make EXIST_MODEL_URL a setting that does nothing.
_nonblank=""
for _r in CHAT EXTRACT EMBED VISION; do
    _v=$(grep -E "^EXIST_MODEL_URL_${_r}=" "$SHIPPED" | head -1 | cut -d= -f2-)
    [[ -z "$_v" ]] || _nonblank+="${_r}=${_v} "
done
[[ -z "$_nonblank" ]] \
    && _ok ".env.exist.shared ships every role endpoint blank" \
    || _fail ".env.exist.shared ships every role endpoint blank" "set: $_nonblank"

# ── honcho actually uses the roles ────────────────────────────────────────────
#
# honcho is the only consumer that talks to TWO roles, so a regression there is
# the one that reintroduces a single hardcoded address for the whole stack. The
# value already ends /v1, so nothing may append another.
grep -q '"EXIST_MODEL_URL_EMBED"' "$HONCHO" \
    && _ok "honcho's embedding block uses the embed endpoint" \
    || _fail "honcho's embedding block uses the embed endpoint"

grep -q '"EXIST_MODEL_URL_EXTRACT"' "$HONCHO" \
    && _ok "honcho's deriver/dialectic blocks use the extract endpoint" \
    || _fail "honcho's deriver/dialectic blocks use the extract endpoint"

grep -qE '"EXIST_MODEL_URL"|EXIST_MODEL_URL[A-Z_]*/v1' "$HONCHO" \
    && _fail "honcho names no bare global endpoint and appends no /v1" \
    || _ok "honcho names no bare global endpoint and appends no /v1"

# Self-check canary: TEST_SELFCHECK=1 forces one failure so this suite's own
# FAIL→non-zero-exit path is itself testable (src/test/run-all.sh selfcheck).
# Without it this suite reported "passed" no matter what — which is the worst
# possible state for the one thing guarding the three endpoint resolvers.
[[ "${TEST_SELFCHECK:-}" == 1 ]] && _fail "selfcheck canary (deliberate failure)"

# ── Summary ───────────────────────────────────────────────────────────────────

echo ""
echo "=== Results: ${PASS} passed, ${FAIL} failed ==="
if [ "$FAIL" -gt 0 ]; then
    printf 'Failed: %s\n' "${FAIL_NAMES[*]}"
    exit 1
fi
