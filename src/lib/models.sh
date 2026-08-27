#!/usr/bin/env bash
# models.sh — change the local model selection.
#
#   ./existential.sh run models
#
# Re-asks the VRAM question from first-run setup and rewrites the EXIST_MODEL_*
# globals in .env.shared. Everything downstream reads those, so this is the only
# place a model needs changing: honcho's config is re-rendered from them,
# openviking's embedding settings come from them, the ollama migrations pull
# whatever they name, and hermes is pointed at them.

set -euo pipefail

if [[ -n "${IN_CONTAINER:-}" ]]; then
    REPO_DIR="/repo"
else
    REPO_DIR="${REPO_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
fi
EXIST_ENV="${REPO_DIR}/.env.shared"

# shellcheck source=src/utils/model-tiers.sh
. "${REPO_DIR}/src/utils/model-tiers.sh"

_C_GREEN=$'\033[32m'
_C_YELLOW=$'\033[33m'
_C_RESET=$'\033[0m'

hr()  { printf '%0.s─' {1..56}; echo; }
die() { echo "Error: $*" >&2; exit 1; }

[ -f "$EXIST_ENV" ] || die "${EXIST_ENV} not found — run ./existential.sh first"
command -v fzf >/dev/null 2>&1 || die "fzf not found"

env_get() { grep -E "^${1}=" "$EXIST_ENV" 2>/dev/null | head -1 | cut -d= -f2-; }
env_set() {
    local key="$1" value="$2"
    if grep -qE "^${key}=" "$EXIST_ENV" 2>/dev/null; then
        sed -i "s|^${key}=.*|${key}=${value}|" "$EXIST_ENV"
    else
        echo "${key}=${value}" >> "$EXIST_ENV"
    fi
}

CURRENT_GB="$(env_get EXIST_VRAM_GB)"
CURRENT_CHAT="$(env_get EXIST_MODEL_CHAT)"
CURRENT_EMBED="$(env_get EXIST_MODEL_EMBED)"

echo ""
hr
echo "  Local model selection"
hr
echo ""
if [[ -n "$CURRENT_CHAT" ]]; then
    echo "  Currently: ${CURRENT_CHAT}${CURRENT_GB:+  (${CURRENT_GB} GB tier)}"
    echo "             ${CURRENT_EMBED:-bge-m3} for embeddings"
else
    echo "  Nothing selected yet."
fi
echo ""

PICKED="$(model_tier_pick "${CURRENT_GB:-$MODEL_TIER_DEFAULT_GB}")"
[[ -n "$PICKED" ]] || { echo "  Unchanged."; echo ""; exit 0; }

# Changing the embedding model after openviking has ingested anything corrupts
# the vector index — the dimensions no longer match what is already stored. No
# tier changes it today, but warn rather than silently break the index if one
# ever does, or if the user has hand-edited EXIST_MODEL_EMBED.
NEW_EMBED="$(model_tier_env "$PICKED" | grep '^EXIST_MODEL_EMBED=' | cut -d= -f2-)"
if [[ -n "$CURRENT_EMBED" && "$CURRENT_EMBED" != "$NEW_EMBED" ]]; then
    echo ""
    echo "  ${_C_YELLOW}⚠${_C_RESET}  Embedding model changes: ${CURRENT_EMBED} → ${NEW_EMBED}"
    echo "     OpenViking's vector index is built for the old dimensions and will"
    echo "     not match. Wipe volumes_local/openviking_data after applying, or"
    echo "     searches will return nonsense."
    echo ""
    read -rp "  Continue? [y/N] " _confirm
    [[ "${_confirm,,}" == "y" ]] || { echo "  Unchanged."; exit 0; }
fi

while IFS='=' read -r _k _v; do
    [[ -n "$_k" ]] && env_set "$_k" "$_v"
done < <(model_tier_env "$PICKED")

IFS=$'\t' read -r _ TLABEL TCHAT TCTX TSIZE _ <<< "$(model_tier_row "$PICKED")"

echo ""
echo "  ${_C_GREEN}✓${_C_RESET}  ${TLABEL} — ${TCHAT} (${TSIZE}), ${TCTX} context"
echo ""
echo "  Apply it:"
echo "    ./existential.sh                      # re-renders honcho's config"
echo "    ./existential.sh run ollama pull-models"
echo "    docker compose restart honcho hermes-agent openviking"
echo ""
echo "  Note: hermes keeps the model already in its config.yaml — it is yours"
echo "  once written. To repoint it:  ./existential.sh run hermes setup"
echo ""
