#!/usr/bin/env bash
# ollama — manual model pull, driven by the global model selection.
#
# This is a manual fallback. Under normal operation the ollama-decree
# migrations (decree/migrations.example/) do exactly this after ollama passes
# its health check — copy them into decree/migrations/ and they run once.
#
# Which models get pulled is NOT decided here: it comes from the "Model
# Selection" block in .env.shared (EXIST_MODEL_CHAT, EXIST_MODEL_EXTRACT,
# EXIST_MODEL_EMBED, EXIST_MODEL_VISION). Change it there and re-run this.
#
# Run manually:
#   ./existential.sh run ollama pull-models

set -euo pipefail

# Self-elevate into existential-adhoc if we're on the host. A local ollama
# publishes no host port — the default OLLAMA_URL is http://ollama:11434, a
# Docker DNS name that only resolves on the exist network — so run from the host
# this script could only ever time out waiting for a server it cannot reach.
# adhoc is on that network, and can equally reach a remote EXIST_OLLAMA_URL.
if [[ -z "${IN_CONTAINER:-}" ]]; then
    _SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
    _REPO="$(cd "$(dirname "$_SCRIPT")/../.." && pwd)"
    _tty=(-T); [[ -t 0 && -t 1 ]] && _tty=(-it)
    exec docker compose -f "${_REPO}/existential-compose.yml" run --rm "${_tty[@]}" \
        --entrypoint "" existential-adhoc bash "/repo${_SCRIPT#"$_REPO"}"
fi

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# existential.sh exports .env.shared before dispatching, but this script is also
# run directly. Source it ourselves so both paths see the same models.
if [ -f "${REPO_DIR}/.env.shared" ]; then
    set -a
    # shellcheck disable=SC1091
    . "${REPO_DIR}/.env.shared"
    set +a
fi

# EXIST_OLLAMA_URL (.env.shared) is the one place the address is named, so a
# stack pointed at an ollama on another host pulls to THAT host. Hardcoding the
# container name here made this action silently unusable in exactly that setup:
# it waited 30 attempts on a name that does not resolve, exited 0, and left the
# models unpulled — which surfaces much later as openviking embedding failures.
OLLAMA_URL="${OLLAMA_URL:-${EXIST_OLLAMA_URL:-http://ollama:11434}}"

MODEL_CHAT="${EXIST_MODEL_CHAT:-}"
MODEL_CHAT_NUM_CTX="${EXIST_MODEL_CHAT_NUM_CTX:-}"
MODEL_EXTRACT="${EXIST_MODEL_EXTRACT:-}"
MODEL_EMBED="${EXIST_MODEL_EMBED:-}"
MODEL_VISION="${EXIST_MODEL_VISION:-}"

hr() { printf '%0.s─' {1..56}; echo; }
die() { echo "Error: $*" >&2; exit 1; }

command -v jq >/dev/null 2>&1 || die "jq not found"
[ -n "$MODEL_CHAT" ] || die "EXIST_MODEL_CHAT is not set in ${REPO_DIR}/.env.shared"

# Roles in pull order; the chat model must land before the num_ctx rebuild.
# A blank value is skipped, which is how EXIST_MODEL_VISION= turns vision off.
declare -a MODELS=()
for m in "$MODEL_CHAT" "$MODEL_EXTRACT" "$MODEL_EMBED" "$MODEL_VISION"; do
    [ -n "$m" ] || continue
    # De-dupe: EXIST_MODEL_EXTRACT defaults to the same tag as chat.
    for seen in ${MODELS[@]+"${MODELS[@]}"}; do
        [ "$seen" = "$m" ] && { m=""; break; }
    done
    [ -n "$m" ] && MODELS+=("$m")
done

# ── Preflight ─────────────────────────────────────────────────────────────────

echo ""
echo "  ollama model setup"
hr
echo ""
echo "  Waiting for ollama at ${OLLAMA_URL}..."
for i in $(seq 1 30); do
    if curl -sf --max-time 5 "${OLLAMA_URL}/api/tags" >/dev/null 2>&1; then
        echo "  ollama ready."
        break
    fi
    [ "$i" -eq 30 ] && die "ollama did not respond after 30 attempts"
    sleep 5
done

# ── Pull models ───────────────────────────────────────────────────────────────

echo ""
# What ollama already has. Two reasons this matters, and neither is speed:
#
#   * EXIST_MODEL_CHAT does not have to be a registry tag. The num_ctx rebuild
#     below writes back to the SAME tag via /api/create, and a user may point
#     EXIST_MODEL_CHAT at a tag they built themselves. /api/pull can never
#     satisfy such a name — it sits on "pulling manifest" indefinitely, which
#     stalls the whole command before the later models are reached.
#   * Re-pulling the chat tag would overwrite that rebuild with the stock
#     context window, silently undoing the thing this script exists to set.
#
# The cost is that an existing tag is never refreshed from upstream. Deleting it
# on the ollama host (`ollama rm <tag>`) is how you ask for a fresh copy.
HAVE_TAGS=$(curl -sf --max-time 10 "${OLLAMA_URL}/api/tags" 2>/dev/null \
    | jq -r '.models[]?.name' 2>/dev/null || true)

_have_model() {
    local want="$1" have
    while IFS= read -r have; do
        [ -n "$have" ] || continue
        # ollama reports "name:latest"; a bare "name" refers to the same tag.
        [ "$have" = "$want" ] && return 0
        [ "$have" = "${want}:latest" ] && return 0
    done <<EOF
${HAVE_TAGS}
EOF
    return 1
}

for model in "${MODELS[@]}"; do
    if _have_model "$model"; then
        echo "  ${model} already present — skipping pull."
        echo ""
        continue
    fi
    echo "  Pulling ${model}..."
    # --max-time so an unsatisfiable name fails the command instead of hanging.
    jq -nc --arg m "$model" '{model: $m}' \
        | curl -fsSL --no-buffer --max-time 3600 "${OLLAMA_URL}/api/pull" \
               -H "Content-Type: application/json" --data @- \
        | while IFS= read -r line; do
            [ -n "$line" ] || continue
            status=$(printf '%s' "$line" | jq -r '.status // empty' 2>/dev/null || true)
            [ -n "$status" ] && printf '\r  %-60s' "$status"
        done
    echo ""
    echo "  Pulled ${model}."
    echo ""
done

# ── Apply the chat context window ─────────────────────────────────────────────
# Mirrors migration 02-set-chat-context.md. The rebuilt model keeps the same
# tag, so every consumer still names exactly one model.

if [ -n "$MODEL_CHAT_NUM_CTX" ]; then
    echo "  Applying num_ctx=${MODEL_CHAT_NUM_CTX} to ${MODEL_CHAT} via /api/create..."
    # Structured fields, not the retired flat `modelfile` string — current ollama
    # rejects the latter with a 400. Keep in step with automations/shared_routines/ollama-pull.sh.
    jq -nc --arg m "$MODEL_CHAT" --arg f "$MODEL_CHAT" \
           --argjson c "$MODEL_CHAT_NUM_CTX" \
           '{model: $m, from: $f, parameters: {num_ctx: $c}}' \
        | curl -fsSL --no-buffer "${OLLAMA_URL}/api/create" \
               -H "Content-Type: application/json" --data @- \
        | while IFS= read -r line; do
            [ -n "$line" ] || continue
            status=$(printf '%s' "$line" | jq -r '.status // empty' 2>/dev/null || true)
            [ -n "$status" ] && echo "  $status"
        done
    echo "  ${MODEL_CHAT} updated."
fi

echo ""
hr
echo ""
echo "  Done. Models available:"
curl -sf "${OLLAMA_URL}/api/tags" | jq -r '.models[]?.name | "  " + .' 2>/dev/null || true
echo ""
