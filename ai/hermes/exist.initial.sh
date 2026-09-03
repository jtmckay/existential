#!/usr/bin/env bash
# hermes — pre-startup init
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Role → endpoint. Sourced, not reimplemented: the fallback to EXIST_OLLAMA_URL
# lives in one place so hermes cannot disagree with honcho or openviking.
# shellcheck source=../../src/utils/model-endpoints.sh
source "${SCRIPT_DIR}/../../src/utils/model-endpoints.sh"

# Skip when running inside a container — docker socket not available in adhoc.
if [[ "${IN_CONTAINER:-}" == "1" ]]; then
    exit 0
fi

# Pre-populate hermes build trees from the image onto the host, so /opt/hermes
# is host-writable. That is what _ensure_honcho_ai below needs: the image's own
# venv is deliberately sealed (stage2-hook.sh: "Do not chown runtime code or
# dependency trees under $INSTALL_DIR" — keeping /opt/hermes root-owned is how
# it stops an agent session from bricking its own gateway), so honcho-ai cannot
# be pip-installed into it in place.
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

    # A NON-EMPTY .venv is the cache marker, not merely a present one. The four
    # trees below are bind-mount sources in docker-compose.yml, so a `docker
    # compose up` that beats this script leaves them existing but empty — and
    # treating that as a valid cache would hand hermes an image whose own .venv,
    # gateway, node_modules and ui-tui are all shadowed by empty directories
    # (which is what "hermes-agent: Restarting (127)" looks like from outside).
    if [[ -f "${cache_dir}/.image_id" ]] && \
       [[ "$(cat "${cache_dir}/.image_id")" == "$img_id" ]] && \
       [[ -n "$(ls -A "${cache_dir}/.venv" 2>/dev/null)" ]]; then
        echo "[hermes] Build cache current (${image##*:})."
        return 0
    fi

    # Same story, one step earlier: those daemon-created directories are
    # root:root, so every write below (the rm, the docker cp, the chown) fails
    # for the user running this. Say so once, with the fix, instead of three
    # times as "Permission denied".
    local -a _stuck=()
    local _p
    for _p in "$cache_dir" "${cache_dir}/.venv" "${cache_dir}/ui-tui" \
              "${cache_dir}/gateway" "${cache_dir}/node_modules"; do
        [[ -e "$_p" && ! -w "$_p" ]] && _stuck+=("${_p#"${SCRIPT_DIR}/"}")
    done
    if [[ "${#_stuck[@]}" -gt 0 ]]; then
        echo "[hermes] Cannot write to the build cache — these are owned by another user:" >&2
        printf '[hermes]   %s\n' "${_stuck[@]}" >&2
        echo "[hermes]" >&2
        echo "[hermes] Docker creates a missing bind-mount source as root, so this happens when" >&2
        echo "[hermes] the stack came up before the cache was extracted. Reclaim them with:" >&2
        echo "[hermes]     docker compose down && ./existential.sh run fix-permissions" >&2
        return 1
    fi

    echo "[hermes] Extracting build trees from image (one-time per version, ~1 min)..."
    # The cache dir must exist BEFORE the first docker cp. `docker cp src dest/`
    # with a missing dest does not create dest and copy into it — it makes dest a
    # copy of src. On a fresh clone that turned hermes_install/ into the venv
    # itself (bin/, lib/, pyvenv.cfg at the top level) with ui-tui, gateway and
    # node_modules as siblings inside it, all four reporting "ok" and no .venv
    # anywhere. Compose then bind-mounted the missing hermes_install/.venv,
    # docker created it empty and root-owned, and that empty dir shadowed the
    # image's real venv — hermes never served. It only looked like "needs a
    # second run" because that first `up` created the dir the copy needed.
    mkdir -p "$cache_dir"
    rm -rf "${cache_dir:?}"/.venv "${cache_dir}"/ui-tui "${cache_dir}"/gateway "${cache_dir}"/node_modules "${cache_dir}"/.image_id

    local cid
    # Unchecked, a failure here degrades into four "(not in image, skipping)"
    # lines and a cache that is silently empty. Stderr is deliberately left
    # unredirected (not `2>&1` into cid): on a fresh clone the image is not
    # pulled yet, so this is where the pull happens, and Docker's pull-progress
    # text would otherwise land inside `cid` alongside the real container ID —
    # every `docker cp "${cid}:..."` below then silently fails against that
    # garbled ref (swallowed by its own `2>/dev/null`), leaving .venv empty
    # while .image_id still gets written as if the cache were ready.
    if ! cid=$(docker create "$image"); then
        echo "[hermes] Could not create a container from ${image}." >&2
        return 1
    fi

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
    if ! chown -R "${uid}:${gid}" "$cache_dir" 2>/dev/null; then
        echo "[hermes] Could not chown ${cache_dir#"${SCRIPT_DIR}/"} to ${uid}:${gid}." >&2
        echo "[hermes] Run: ./existential.sh run fix-permissions" >&2
        return 1
    fi
    echo "$img_id" > "${cache_dir}/.image_id"
    echo "[hermes] Build cache ready — future container restarts will skip the chown."
}

_ensure_hermes_install

# Install honcho-ai into the cached venv so the honcho memory plugin is importable.
# Runs after _ensure_hermes_install, which is expected to have populated the
# venv by now — but generate-compose.ts pre-creates the directory itself (empty)
# well before this script runs, so its presence alone proves nothing; see the
# non-emptiness check below.
_ensure_honcho_ai() {
    local venv="${SCRIPT_DIR}/hermes_install/.venv"
    # Non-empty, not merely present: generate-compose.ts pre-creates .venv as an
    # empty directory at render time (ensureBindSource), before this script ever
    # runs — the same reason _ensure_hermes_install above uses `ls -A` as its own
    # cache marker. A bare `-d` here would always be true from the first run
    # onward and never actually catch "not yet extracted."
    if [[ ! -d "${venv}" ]] || [[ -z "$(ls -A "${venv}" 2>/dev/null)" ]]; then
        echo "[hermes] .venv not yet extracted — honcho-ai will be installed on next run." >&2
        return 0
    fi
    # Check the tree, not `python -c "import honcho"`: .venv/bin/python is a
    # symlink to the *container's* interpreter, so running it on the host either
    # fails or resolves to an unrelated python — either way the import always
    # said "missing" and every run paid for a fresh pip install.
    if compgen -G "${venv}/lib/python*/site-packages/honcho/__init__.py" >/dev/null; then
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
# Print just the model: block of a hermes config.yaml — from the `model:` line
# to the next top-level key. The shipped example is ~1900 lines and mentions
# base_url and context_length all over it, so every read has to be scoped.
_hermes_model_block() {
    awk '/^model:/ { f = 1; print; next } f && /^[^[:space:]#]/ { exit } f { print }' "$1"
}

# Same, for the memory: block — memory.provider is the external-provider
# activation key, and `provider:` appears in several other blocks.
_hermes_memory_block() {
    awk '/^memory:/ { f = 1; print; next } f && /^[^[:space:]#]/ { exit } f { print }' "$1"
}

# True when config.yaml's mcp_servers: block already declares server $2 — the
# per-server guard, so enabling one service later doesn't re-add another.
_hermes_has_mcp_server() {
    [[ -f "$1" ]] || return 1
    awk '/^mcp_servers:/ { f = 1; next } f && /^[^[:space:]#]/ { exit } f { print }' "$1" \
        | grep -qE "^[[:space:]]{2}$2:[[:space:]]*$"
}

# One key out of the model: block. Scoped to the block on purpose — base_url and
# context_length appear elsewhere in a hermes config, so an unscoped grep reads
# the wrong line.
_hermes_model_field() {
    _hermes_model_block "$1" \
        | grep -m1 -E "^[[:space:]]*${2}:" \
        | sed -E "s/^[[:space:]]*${2}:[[:space:]]*//; s/[[:space:]]*(#.*)?$//; s/[\"']//g" || true
}

# True when the model: block still points at an ollama endpoint we own, i.e.
# provider "custom" plus a host:11434 base_url. That is the same test openviking
# applies to ov.conf's api_base, and it is what separates "existential configured
# this" from "the user chose Anthropic". The endpoint pattern deliberately
# matches ANY host on :11434, not just the currently configured one — otherwise
# moving the chat role to another box would look like a deliberate choice and
# freeze the config at the dead address.
_hermes_model_is_ours() {
    local cfg="$1" provider base
    provider=$(_hermes_model_field "$cfg" provider)
    base=$(_hermes_model_field "$cfg" base_url)
    [[ "$provider" == "custom" ]] || return 1
    [[ "$base" =~ ^https?://[^/]+:11434(/v1)?$ ]] || return 1
    return 0
}

# True when the model: block is still the image's stock example AND no provider
# key is configured anywhere — i.e. nobody has chosen a provider yet, so we may.
_hermes_model_is_stock() {
    local cfg="$1" provider key
    provider=$(_hermes_model_block "$cfg" | grep -m1 -E '^[[:space:]]*provider:' \
        | sed -E 's/^[[:space:]]*provider:[[:space:]]*//; s/[[:space:]]*(#.*)?$//; s/["'"'"']//g' || true)
    [[ -z "$provider" || "$provider" == "auto" ]] || return 1
    for key in ANTHROPIC_API_KEY OPENAI_API_KEY OPENROUTER_API_KEY GOOGLE_API_KEY \
               GROQ_API_KEY MISTRAL_API_KEY NOUS_API_KEY; do
        [[ -n "${!key:-}" ]] && return 1
        [[ -f "${SCRIPT_DIR}/.env" ]] && grep -qE "^${key}=.+" "${SCRIPT_DIR}/.env" && return 1
    done
    return 0
}

# Rewrite default/provider/base_url/context_length inside the existing model:
# block, in place, leaving the rest of the file (comments included) untouched.
_hermes_write_model_block() {
    local cfg="$1" chat="$2" ctx="$3" url="$4" tmp
    tmp=$(mktemp)
    awk -v chat="$chat" -v ctx="$ctx" -v url="$url" '
        function fill() {
            if (!d) print "  default: \"" chat "\""
            if (!p) print "  provider: \"custom\""
            if (!b) print "  base_url: \"" url "/v1\""
            if (!c) print "  context_length: " ctx
        }
        !f && /^model:/                       { f = 1; print; next }
        f && /^[^[:space:]#]/                 { fill(); f = 0; done = 1; print; next }
        f && !d && /^[[:space:]]*default:/    { print "  default: \"" chat "\""; d = 1; next }
        f && !p && /^[[:space:]]*provider:/   { print "  provider: \"custom\""; p = 1; next }
        f && !b && /^[[:space:]]*base_url:/   { print "  base_url: \"" url "/v1\""; b = 1; next }
        f && !c && /^[[:space:]]*context_length:/ { print "  context_length: " ctx; c = 1; next }
        { print }
        END { if (f) fill() }
    ' "$cfg" > "$tmp" && cat "$tmp" > "$cfg"
    rm -f "$tmp"
}

_seed_hermes_config() {
    local repo="${SCRIPT_DIR}/../.."
    local data="${repo}/volumes/hermes_agent_data"
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
    # The CHAT role's endpoint (.env.shared, "Model Endpoints") — hermes is the
    # chat consumer, so it follows EXIST_OLLAMA_URL_CHAT and only falls back to
    # the global EXIST_OLLAMA_URL when that is blank. Set the role key to put the
    # agent's model on its own box.
    local ollama_url; ollama_url="$(endpoint_for chat)"
    if [[ -z "$chat" ]]; then
        echo "[hermes] EXIST_MODEL_CHAT unset — skipping model config." >&2
    elif [[ ! -f "$cfg" ]] || ! grep -qE '^model:' "$cfg"; then
        echo "[hermes] Pointing hermes at ollama (${chat}) at ${ollama_url}..."
        cat >> "$cfg" <<EOF
model:
  default: ${chat}
  provider: custom
  base_url: ${ollama_url}/v1
  context_length: ${ctx:-65536}
EOF
    elif _hermes_model_is_stock "$cfg"; then
        # The container seeds cli-config.yaml.example into /opt/data on first
        # boot when config.yaml is absent — which is the normal order, since the
        # volume starts empty. That example ships a full model: block
        # (provider: "auto", an anthropic default, an openrouter base_url), so a
        # "does it have a model: block" test says yes and hermes then starts with
        # no provider it can actually reach: "No inference provider configured".
        # Stock example + no provider key anywhere = nobody has chosen, so choose.
        echo "[hermes] config.yaml holds the image's stock model: block — pointing it at ollama (${chat} @ ${ollama_url})."
        _hermes_write_model_block "$cfg" "$chat" "${ctx:-65536}" "$ollama_url"
    elif _hermes_model_is_ours "$cfg"; then
        # The block still points at ollama, so it is .env.shared's to own —
        # "Model choice is global, never per-service" (CLAUDE.md). Without this,
        # changing EXIST_MODEL_CHAT silently did nothing here: hermes kept the
        # first model it was ever given while every other consumer moved, and the
        # only symptom was the agent answering from a model you thought you had
        # replaced. Reconciles the endpoint too, so moving the chat role to
        # another box follows.
        local cur_model cur_base cur_ctx
        cur_model=$(_hermes_model_field "$cfg" default)
        cur_base=$(_hermes_model_field "$cfg" base_url)
        cur_ctx=$(_hermes_model_field "$cfg" context_length)
        if [[ "$cur_model" == "$chat" && "$cur_base" == "${ollama_url}/v1" \
              && ( -z "$ctx" || "$cur_ctx" == "$ctx" ) ]]; then
            echo "[hermes] config.yaml already current (${chat} @ ${ollama_url}) — leaving it alone."
        else
            echo "[hermes] config.yaml has ${cur_model} @ ${cur_base}; .env.shared says ${chat} @ ${ollama_url}/v1 — reconciling."
            _hermes_write_model_block "$cfg" "$chat" "${ctx:-65536}" "$ollama_url"
        fi
    else
        # Not ours: the user pointed hermes at a provider of their own, so their
        # choice of model, provider and endpoint survives. context_length is the
        # one exception: it is not a preference, it is a fact about how
        # EXIST_MODEL_CHAT was built, and a stale value here is unobservable from
        # the outside. Hermes packs a prompt to whatever this says and ollama
        # truncates the overflow silently, which reads as the agent ignoring its
        # instructions. So reconcile this single line and leave every other line
        # alone.
        local have
        have=$(_hermes_model_block "$cfg" | grep -m1 -E '^[[:space:]]*context_length:' | grep -oE '[0-9]+' || true)
        if [[ -z "$ctx" ]]; then
            echo "[hermes] config.yaml has a model: block; EXIST_MODEL_CHAT_NUM_CTX unset — leaving it alone."
        elif [[ -z "$have" ]]; then
            echo "[hermes] config.yaml has a model: block but no context_length — leaving it alone." >&2
        elif [[ "$have" == "$ctx" ]]; then
            echo "[hermes] config.yaml already has a model: block (context_length=${ctx}) — leaving it alone."
        else
            echo "[hermes] config.yaml context_length=${have} but EXIST_MODEL_CHAT_NUM_CTX=${ctx} — reconciling."
            sed -i -E "0,/^[[:space:]]*context_length:.*/s//  context_length: ${ctx}/" "$cfg"
        fi

        # base_url gets the same treatment, but only while it still holds an
        # ollama address — one the user pointed at their own provider is a
        # preference and survives. Anything else and EXIST_OLLAMA_URL would be a
        # setting that silently does nothing, so say so.
        local have_url
        have_url=$(_hermes_model_block "$cfg" | grep -m1 -E '^[[:space:]]*base_url:' \
            | sed -E 's/^[[:space:]]*base_url:[[:space:]]*//; s/[[:space:]]*(#.*)?$//; s/^"//; s/"$//' || true)
        if [[ -z "$have_url" || "$have_url" == "${ollama_url}/v1" ]]; then
            :
        elif [[ "$have_url" =~ ^https?://[^/]+:11434(/v1)?$ ]]; then
            echo "[hermes] config.yaml base_url=${have_url} but the chat endpoint is ${ollama_url} — reconciling."
            sed -i -E "0,/^[[:space:]]*base_url:.*/s##  base_url: ${ollama_url}/v1#" "$cfg"
        else
            echo "[hermes] config.yaml base_url=${have_url} (not an ollama endpoint) — leaving it alone; the chat endpoint setting is ignored here."
        fi
    fi

    # ── MCP servers ──────────────────────────────────────────────────────────
    # Only for services actually enabled — an MCP entry pointing at a container
    # that does not exist makes hermes retry a dead endpoint on every task.
    #
    # Per-server, not all-or-nothing: enabling firecrawl (or openviking) months
    # after hermes first came up must still register it, and an all-or-nothing
    # guard on `mcp_servers:` would silently skip it forever. Each entry is
    # added only when its own key is absent, so a server the user edited,
    # removed or renamed by hand is left alone.
    local mcp_block=""
    if [[ "${EXIST_IS_AI_OPENVIKING:-false}" == "true" ]] && ! _hermes_has_mcp_server "$cfg" openviking; then
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
    # firecrawl-mcp holds FIRECRAWL_API_KEY itself (see its compose env), so
    # hermes reaches it unauthenticated over the exist network — no header here.
    if [[ "${EXIST_IS_AI_FIRECRAWL:-false}" == "true" ]] && ! _hermes_has_mcp_server "$cfg" firecrawl; then
        mcp_block+="  firecrawl:
    url: \"http://firecrawl-mcp:3003/mcp\"
"
    fi
    if [[ -z "$mcp_block" ]]; then
        :
    elif [[ -f "$cfg" ]] && grep -qE '^mcp_servers:' "$cfg"; then
        # Splice into the existing block rather than appending a second
        # top-level mcp_servers: key, which YAML would resolve to the last one.
        echo "[hermes] Registering MCP servers..."
        local tmp
        tmp=$(mktemp)
        awk -v block="$mcp_block" '!f && /^mcp_servers:/ { print; printf "%s", block; f = 1; next } { print }' \
            "$cfg" > "$tmp" && cat "$tmp" > "$cfg"
        rm -f "$tmp"
    else
        echo "[hermes] Registering MCP servers..."
        printf 'mcp_servers:\n%s' "$mcp_block" >> "$cfg"
    fi

    # ── honcho memory ────────────────────────────────────────────────────────
    # Two writes, because hermes splits them:
    #   honcho.json           — the plugin's own connection/identity config,
    #                           read at $HERMES_HOME/honcho.json before ~/.hermes.
    #   config.yaml memory.provider — the activation key. Without it hermes
    #                           reports "(none — built-in only)" and never loads
    #                           the plugin, however complete honcho.json is.
    # `hermes memory setup honcho` writes both; so do we.
    # HONCHO_BASE_URL is also passed in compose as the plugin's baseUrl fallback.
    if [[ "${EXIST_IS_AI_HONCHO:-false}" != "true" ]]; then
        :
    else
        if [[ -f "$honcho_cfg" ]]; then
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

        # Only one external provider can be active at a time, so a provider the
        # user already chose is their choice and survives.
        local have_provider
        have_provider=$(_hermes_memory_block "$cfg" 2>/dev/null \
            | grep -m1 -E '^[[:space:]]*provider:' \
            | sed -E 's/^[[:space:]]*provider:[[:space:]]*//; s/[[:space:]]*(#.*)?$//; s/["'"'"']//g' || true)
        if [[ -n "$have_provider" ]]; then
            echo "[hermes] config.yaml memory provider is already ${have_provider} — leaving it alone."
        elif [[ ! -f "$cfg" ]] || ! grep -qE '^memory:' "$cfg"; then
            printf 'memory:\n  provider: honcho\n' >> "$cfg"
            echo "[hermes] Activated honcho as hermes' memory provider."
        else
            local tmp
            tmp=$(mktemp)
            awk '!f && /^memory:/ { print; print "  provider: honcho"; f = 1; next } { print }' \
                "$cfg" > "$tmp" && cat "$tmp" > "$cfg"
            rm -f "$tmp"
            echo "[hermes] Activated honcho as hermes' memory provider."
        fi
    fi

    # The gateway runs as the host uid; anything seeded as root here would be
    # unreadable to it.
    chown -R "${EXIST_PUID:-$(id -u)}:${EXIST_PGID:-$(id -g)}" "$data" 2>/dev/null || true
}

_seed_hermes_config
