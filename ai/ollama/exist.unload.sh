#!/usr/bin/env bash
# ollama — evict the resident model from memory.
#
#   ./existential.sh run ollama unload [model]
#
# Ollama keeps a model resident for OLLAMA_KEEP_ALIVE (10m by default) and
# serves every request from that already-loaded instance. An instance carries
# the num_ctx it was loaded with, so after `run ollama pull-models` rebuilds a
# tag at a new context the OLD instance keeps answering at the OLD size until it
# expires — which reads as the rebuild having silently done nothing.
#
# This drops it. The next request reloads from the rebuilt tag.
#
# With no argument it unloads EXIST_MODEL_CHAT. Pass a tag to unload something
# else (e.g. the embedding model).

set -euo pipefail

# Self-elevate into existential-adhoc if we're on the host. ollama publishes no
# host port — OLLAMA_URL is http://ollama:11434, a Docker DNS name that only
# resolves on the exist network.
if [[ -z "${IN_CONTAINER:-}" ]]; then
    _SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
    _REPO="$(cd "$(dirname "$_SCRIPT")/../.." && pwd)"
    _tty=(-T); [[ -t 0 && -t 1 ]] && _tty=(-it)
    exec docker compose -f "${_REPO}/existential-compose.yml" run --rm "${_tty[@]}" \
        --entrypoint "" existential-adhoc bash "/repo${_SCRIPT#"$_REPO"}" "$@"
fi

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

if [ -f "${REPO_DIR}/.env.shared" ]; then
    set -a
    # shellcheck disable=SC1091
    . "${REPO_DIR}/.env.shared"
    set +a
fi

OLLAMA_URL="${OLLAMA_URL:-http://ollama:11434}"
MODEL="${1:-${EXIST_MODEL_CHAT:-}}"

die() { echo "Error: $*" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || die "jq not found"
[ -n "$MODEL" ] || die "no model given and EXIST_MODEL_CHAT is not set in ${REPO_DIR}/.env.shared"

echo ""
echo "  Resident before:"
curl -sf --max-time 5 "${OLLAMA_URL}/api/ps" \
    | jq -r '.models[]? | "    \(.model)  \(.size/1024/1024|floor)MB  ctx \(.context_length)"' \
    2>/dev/null || echo "    (none)"

# keep_alive: 0 tells ollama to expire the model immediately. No prompt is sent,
# so nothing is generated and no KV cache is allocated. The API confirms with
# done_reason: "unload" and stamps expires_at to now.
echo ""
echo "  Unloading ${MODEL}..."
RESP=$(jq -nc --arg m "$MODEL" '{model: $m, keep_alive: 0}' \
    | curl -fsS "${OLLAMA_URL}/api/generate" \
           -H "Content-Type: application/json" --data @- 2>/dev/null) \
    || die "unload request failed — is ${MODEL} a model ollama knows?"

echo "$RESP" | jq -e '.done_reason == "unload"' >/dev/null 2>&1 \
    || die "ollama did not accept the unload: ${RESP}"

# Expiry is stamped synchronously but the instance is reaped a moment later, so
# /api/ps can still list it. Poll for it to disappear, then fall back to
# reporting the expiry — an expired instance is reloaded on the next request
# either way, which is the outcome that actually matters.
GONE=false
for _ in $(seq 1 10); do
    if curl -sf --max-time 5 "${OLLAMA_URL}/api/ps" \
        | jq -e --arg m "$MODEL" '[.models[]? | select(.model == $m)] | length == 0' \
        >/dev/null 2>&1; then
        GONE=true; break
    fi
    sleep 1
done

echo ""
if [ "$GONE" = true ]; then
    echo "  Evicted. The next request reloads ${MODEL} from the tag on disk."
else
    echo "  Marked for eviction (expired $(echo "$RESP" | jq -r '.created_at'));"
    echo "  ollama reaps it shortly. The next request reloads it from the tag on disk."
fi

echo ""
echo "  Resident now:"
curl -sf --max-time 5 "${OLLAMA_URL}/api/ps" \
    | jq -r '.models[]? | "    \(.model)  \(.size/1024/1024|floor)MB  ctx \(.context_length)  expires \(.expires_at)"' \
    2>/dev/null | grep . || echo "    (none)"
echo ""
