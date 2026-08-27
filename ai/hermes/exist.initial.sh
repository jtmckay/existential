#!/usr/bin/env bash
# hermes — pre-startup init
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Skip when running inside a container — docker socket not available in adhoc.
if [[ "${IN_CONTAINER:-}" == "1" ]]; then
    exit 0
fi

# Pre-populate hermes build trees from the image so stage2-hook.sh skips its
# 5-min recursive chown on every container restart. The hook gates the entire
# chown block on .venv ownership: if .venv is already uid ${EXIST_PUID:-1000},
# it skips chowning .venv, ui-tui, gateway, and node_modules.
#
# We extract once per image version (tracked by image digest in .image_id).
# On fresh clone or after a new image pull: re-extracts and chowns on the host
# (~1 min, much faster than overlayfs chown inside the container).
_ensure_hermes_install() {
    local cache_dir="${SCRIPT_DIR}/hermes_install"
    local image
    image=$(grep -m1 'image:.*hermes-agent' "${SCRIPT_DIR}/docker-compose.yml" \
            | sed 's/[[:space:]]*image:[[:space:]]*//')

    if [[ -z "${image:-}" ]]; then
        echo "[hermes] Could not find hermes-agent image in docker-compose.yml — skipping build cache." >&2
        return 0
    fi

    local img_id
    img_id=$(docker inspect --format='{{.Id}}' "$image" 2>/dev/null) || {
        echo "[hermes] Image $image not pulled yet — pull it, then re-run ./existential.sh run." >&2
        return 0
    }

    if [[ -f "${cache_dir}/.image_id" ]] && \
       [[ "$(cat "${cache_dir}/.image_id")" == "$img_id" ]] && \
       [[ -d "${cache_dir}/.venv" ]]; then
        echo "[hermes] Build cache current (${image##*:})."
        return 0
    fi

    echo "[hermes] Extracting build trees from image (one-time per version, ~1 min)..."
    rm -rf "${cache_dir:?}"/.venv "${cache_dir}"/ui-tui "${cache_dir}"/gateway "${cache_dir}"/node_modules "${cache_dir}"/.image_id

    local cid
    cid=$(docker create "$image" 2>/dev/null)

    for tree in .venv ui-tui gateway node_modules; do
        printf "[hermes]   %-14s " "$tree"
        if docker cp "${cid}:/opt/hermes/${tree}" "${cache_dir}/" 2>/dev/null; then
            echo "ok"
        else
            echo "(not in image, skipping)"
        fi
    done

    docker rm "$cid" >/dev/null 2>&1

    local uid="${EXIST_PUID:-$(id -u)}"
    local gid="${EXIST_PGID:-$(id -g)}"
    echo "[hermes] Chowning cache to ${uid}:${gid}..."
    chown -R "${uid}:${gid}" "$cache_dir"
    echo "$img_id" > "${cache_dir}/.image_id"
    echo "[hermes] Build cache ready — future container restarts will skip the chown."
}

_ensure_hermes_install

# Install honcho-ai into the cached venv so the honcho memory plugin is importable.
# Runs after _ensure_hermes_install so the venv is guaranteed to exist.
_ensure_honcho_ai() {
    local venv="${SCRIPT_DIR}/hermes_install/.venv"
    if [[ ! -d "${venv}" ]]; then
        echo "[hermes] .venv not yet extracted — honcho-ai will be installed on next run." >&2
        return 0
    fi
    if "${venv}/bin/python" -c "import honcho" 2>/dev/null; then
        echo "[hermes] honcho-ai already installed."
        return 0
    fi
    local image
    image=$(grep -m1 'image:.*hermes-agent' "${SCRIPT_DIR}/docker-compose.yml" \
            | sed 's/[[:space:]]*image:[[:space:]]*//')
    echo "[hermes] Installing honcho-ai==2.1.2 into venv..."
    docker run --rm \
        -v "${venv}:/opt/hermes/.venv" \
        -e UV_LINK_MODE=copy \
        --entrypoint uv \
        "${image}" \
        pip install "honcho-ai==2.1.2" --python /opt/hermes/.venv/bin/python
    echo "[hermes] honcho-ai installed."
}

_ensure_honcho_ai

# ── First-boot wiring ─────────────────────────────────────────────────────────
# Seed hermes' own config so the agent is usable on the FIRST `docker compose
# up -d` instead of after three manual commands. Everything here was previously
# a documented post-startup step:
#
#   hermes model                              → the model: block below
#   ./existential.sh run openviking mcp       → mcp_servers.openviking
#   ./existential.sh run firecrawl mcp        → mcp_servers.firecrawl
#   hermes memory setup honcho                → honcho.json
#
# Those commands still exist and still work — this only fills in what is absent.
# Every write is guarded on the key not already being present, so a user who has
# run `hermes model` (or edited the file by hand) keeps their choice. That is why
# there are no sentinels: the config itself is the state.
#
# Schemas are hermes'/honcho's own, not invented here:
#   https://hermes-agent.nousresearch.com/docs/integrations/providers  (model:)
#   https://hermes-agent.nousresearch.com/docs/user-guide/features/mcp (mcp_servers:)
#   https://docs.honcho.dev/v3/guides/integrations/hermes              (honcho.json)
_seed_hermes_config() {
    local repo="${SCRIPT_DIR}/../.."
    local data="${repo}/volumes_local/hermes_agent_data"
    local cfg="${data}/config.yaml"
    local honcho_cfg="${data}/honcho.json"

    # existential.sh exports .env.shared before running initials, but this script
    # is also runnable directly via `./existential.sh run hermes`.
    if [[ -f "${repo}/.env.shared" ]]; then
        set -a
        # shellcheck disable=SC1091
        . "${repo}/.env.shared"
        set +a
    fi

    mkdir -p "$data"

    # ── model ────────────────────────────────────────────────────────────────
    # Local ollama is reached through hermes' "custom endpoint" provider — see
    # the Ollama section of the providers doc. context_length must match the
    # num_ctx the model was actually built with, or hermes packs a prompt ollama
    # will silently truncate.
    local chat="${EXIST_MODEL_CHAT:-}"
    local ctx="${EXIST_MODEL_CHAT_NUM_CTX:-}"
    if [[ -z "$chat" ]]; then
        echo "[hermes] EXIST_MODEL_CHAT unset — skipping model config." >&2
    elif [[ -f "$cfg" ]] && grep -qE '^model:' "$cfg"; then
        echo "[hermes] config.yaml already has a model: block — leaving it alone."
    else
        echo "[hermes] Pointing hermes at ollama (${chat})..."
        cat >> "$cfg" <<EOF
model:
  default: ${chat}
  provider: custom
  base_url: http://ollama:11434/v1
  context_length: ${ctx:-32768}
EOF
    fi

    # ── MCP servers ──────────────────────────────────────────────────────────
    # Only for services actually enabled — an MCP entry pointing at a container
    # that does not exist makes hermes retry a dead endpoint on every task.
    if [[ -f "$cfg" ]] && grep -qE '^mcp_servers:' "$cfg"; then
        echo "[hermes] config.yaml already has mcp_servers: — leaving it alone."
    else
        local mcp_block=""
        if [[ "${EXIST_IS_AI_OPENVIKING:-false}" == "true" ]]; then
            local ov_key
            ov_key=$(grep -m1 '^OPENVIKING_API_KEY=' "${repo}/ai/openviking/.env" 2>/dev/null | cut -d= -f2-)
            if [[ -n "$ov_key" ]]; then
                mcp_block+="  openviking:
    url: \"http://openviking:1933/mcp\"
    headers:
      Authorization: \"Bearer ${ov_key}\"
"
            else
                echo "[hermes] openviking enabled but OPENVIKING_API_KEY not found — skipping its MCP entry." >&2
            fi
        fi
        if [[ "${EXIST_IS_AI_FIRECRAWL:-false}" == "true" ]]; then
            mcp_block+="  firecrawl:
    url: \"http://firecrawl-mcp:3003/mcp\"
"
        fi
        if [[ -n "$mcp_block" ]]; then
            echo "[hermes] Registering MCP servers..."
            printf 'mcp_servers:\n%s' "$mcp_block" >> "$cfg"
        fi
    fi

    # ── honcho memory ────────────────────────────────────────────────────────
    # Separate file, checked at $HERMES_HOME/honcho.json before ~/.hermes.
    # HONCHO_BASE_URL is already passed in compose as the plugin's fallback;
    # this is what actually turns the provider on.
    if [[ "${EXIST_IS_AI_HONCHO:-false}" != "true" ]]; then
        :
    elif [[ -f "$honcho_cfg" ]]; then
        echo "[hermes] honcho.json already present — leaving it alone."
    else
        echo "[hermes] Enabling honcho memory..."
        cat > "$honcho_cfg" <<EOF
{
  "baseUrl": "http://honcho:8000",
  "hosts": {
    "hermes": {
      "enabled": true,
      "aiPeer": "hermes",
      "peerName": "${EXIST_USERNAME:-user}",
      "workspace": "hermes"
    }
  }
}
EOF
    fi

    # The gateway runs as the host uid; anything seeded as root here would be
    # unreadable to it.
    chown -R "${EXIST_PUID:-$(id -u)}:${EXIST_PGID:-$(id -g)}" "$data" 2>/dev/null || true
}

_seed_hermes_config
