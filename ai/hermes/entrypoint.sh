#!/usr/bin/env bash
# hermes-agent container entrypoint — installs decree and claude-code into the
# persistent data volume, provisions the profiles declared in ai/hermes/profiles/,
# then chains to the image's s6-overlay init (/init)
# which handles user-remapping (HERMES_UID:HERMES_GID) before starting the gateway.
set -euo pipefail

TOOLS_DIR="/opt/data/.tools"

# All installs land in the hermes_agent_data volume so they survive restarts.
export RUSTUP_HOME="$TOOLS_DIR/rustup"
export CARGO_HOME="$TOOLS_DIR/cargo"
NPM_GLOBAL="$TOOLS_DIR/npm-global"
export PATH="$CARGO_HOME/bin:$NPM_GLOBAL/bin:$PATH"

# ── Rust / cargo ──────────────────────────────────────────────────────────────
if [[ ! -x "$CARGO_HOME/bin/cargo" ]]; then
    echo "[hermes-entrypoint] Installing Rust via rustup..."
    curl -fsSL https://sh.rustup.rs \
        | sh -s -- -y --no-modify-path --default-toolchain stable
fi

# ── decree ────────────────────────────────────────────────────────────────────
# .crates.toml records every `cargo install`-ed crate with its version.
DECREE_VERSION="0.4.2"
if ! grep -qF "\"decree $DECREE_VERSION " "$CARGO_HOME/.crates.toml" 2>/dev/null; then
    echo "[hermes-entrypoint] Installing decree $DECREE_VERSION..."
    cargo install decree --version "$DECREE_VERSION"
fi

# ── claude-code ───────────────────────────────────────────────────────────────
if [[ ! -x "$NPM_GLOBAL/bin/claude" ]]; then
    echo "[hermes-entrypoint] Installing @anthropic-ai/claude-code..."
    npm install -g --prefix "$NPM_GLOBAL" @anthropic-ai/claude-code
fi

# ── profiles ──────────────────────────────────────────────────────────────────
# Provision one hermes profile per directory in /opt/profile-defs (the repo's
# ai/hermes/profiles/, mounted read-only). A profile is its own HERMES_HOME,
# served at /p/<name>/v1 — see that directory's README for the why.
#
# This runs here, and only here, because it is the one place that can: the
# hermes CLI lives in this image and the profiles live in this container's data
# volume, so the host would need `docker exec` and a decree migration cannot
# reach either (no Docker socket, and the repo is mounted read-only there).
# CLAUDE.md rule 6 — config the service owns, written by its own entrypoint.
#
# Every boot, idempotent, no sentinels. An existing profile keeps its
# config.yaml; delete volumes/hermes_agent_data/profiles/<name> to rebuild one.
PROFILE_DEFS="/opt/profile-defs"
PROFILES_DIR="/opt/data/profiles"

# One key out of a profile.yml. Not yq — this image has none, and the format is
# deliberately three flat keys so grep is enough.
_pdef() {
    grep -m1 "^${2}:" "$1" 2>/dev/null | sed "s/^${2}:[[:space:]]*//; s/[[:space:]]*$//"
}

# One mcp_servers entry, by name. An unknown name is skipped with a warning
# rather than written out — an MCP entry pointing at nothing makes hermes retry
# a dead endpoint on every task.
_mcp_entry() {
    case "$1" in
        openviking)
            if [[ -z "${OPENVIKING_API_KEY:-}" ]]; then
                echo "[hermes-entrypoint] openviking requested but OPENVIKING_API_KEY is unset — skipping." >&2
                return 0
            fi
            printf '  openviking:\n    url: "http://openviking:1933/mcp"\n    headers:\n      Authorization: "Bearer %s"\n' \
                "$OPENVIKING_API_KEY"
            ;;
        firecrawl)
            printf '  firecrawl:\n    url: "http://firecrawl-mcp:3003/mcp"\n'
            ;;
        *)
            echo "[hermes-entrypoint] Unknown MCP server '${1}' — skipping." >&2
            ;;
    esac
}

# The default profile's model block, rebuilt from its four meaningful keys.
# Departments inherit the model rather than naming one, so the stack's single
# model choice stays a single choice. The block is not copied verbatim because
# hermes' shipped config.yaml carries ~200 lines of commented provider docs
# inside model:, which would bury the three lines that actually differ.
#
# exist.initial.sh writes this block on the host before `docker compose up`, so
# it is present by the time this runs — including on a first boot.
_model_block() {
    local raw key val out=""
    [[ -f /opt/data/config.yaml ]] || return 0
    raw="$(awk '/^model:/ { f = 1; next } f && /^[^[:space:]#]/ { exit } f { print }' /opt/data/config.yaml)"
    for key in default provider base_url context_length; do
        val="$(printf '%s\n' "$raw" | grep -m1 -E "^[[:space:]]+${key}:" \
            | sed -E "s/^[[:space:]]*${key}:[[:space:]]*//; s/[[:space:]]*(#.*)?$//; s/^\"//; s/\"$//")"
        [[ -z "$val" ]] && continue
        case "$key" in
            context_length) out+="  ${key}: ${val}"$'\n' ;;
            *)              out+="  ${key}: \"${val}\""$'\n' ;;
        esac
    done
    # An `if`, not `[[ ]] &&`: last command in the function, so an empty
    # block would return 1 and set -e would kill the entrypoint at the
    # `_model="$(_model_block)"` assignment — before the warning below.
    if [[ -n "$out" ]]; then printf 'model:\n%s' "$out"; fi
}

if [[ -d "$PROFILE_DEFS" ]]; then
    _model="$(_model_block)"
    if [[ -z "$_model" ]]; then
        # Not fatal: the gateway still serves the default profile. A department
        # with no model would answer nothing, so say why rather than build one.
        echo "[hermes-entrypoint] No model: block in /opt/data/config.yaml — skipping profiles." >&2
    else
        for _def in "$PROFILE_DEFS"/*/profile.yml; do
            [[ -f "$_def" ]] || continue
            _name="$(basename "$(dirname "$_def")")"
            _dir="${PROFILES_DIR}/${_name}"

            if [[ -d "$_dir" ]]; then
                echo "[hermes-entrypoint] profile ${_name}: exists, leaving it alone."
            else
                echo "[hermes-entrypoint] profile ${_name}: creating..."
                # --no-skills: a department's skills are the agents you install
                # into it. Inheriting the default profile's bundled set would put
                # every tool description back in the prompt, which is the cost
                # this whole split exists to avoid.
                /opt/hermes/.venv/bin/hermes profile create "$_name" \
                    --no-skills --no-alias --description "$(_pdef "$_def" description)" >/dev/null
            fi

            # Written only when absent, so an edited profile is kept.
            if [[ ! -f "${_dir}/config.yaml" ]]; then
                _toolsets="$(_pdef "$_def" toolsets)"
                _mcp="$(_pdef "$_def" mcp)"
                _mcp_yaml=""
                # $( ) strips trailing newlines, so put one back: without it a
                # second MCP server lands on the first one's last line and the
                # whole mcp_servers: block is invalid YAML.
                for _one in ${_mcp//,/ }; do _mcp_yaml+="$(_mcp_entry "$_one")"$'\n'; done
                {
                    printf '# %s profile — generated from ai/hermes/profiles/%s/profile.yml.\n' "$_name" "$_name"
                    printf '# Edited by hand? This file is written only when absent, so it is kept.\n'
                    printf '%s\n' "$_model"
                    printf '\nplatform_toolsets:\n  api_server: %s\n' \
                        "$([[ -n "$_toolsets" ]] && echo "[${_toolsets}]" || echo '[]')"
                    # An `if`, not `[[ ]] &&`: this is the last command in the
                    # group, so a false test makes the whole group exit non-zero
                    # and set -e would kill the entrypoint on any profile that
                    # declares no MCP servers — the router, for one.
                    if [[ -n "$_mcp_yaml" ]]; then printf '\nmcp_servers:\n%s' "$_mcp_yaml"; fi
                } > "${_dir}/config.yaml"
                echo "[hermes-entrypoint]   config.yaml written (toolsets: ${_toolsets:-none}, mcp: ${_mcp:-none})."
            fi

            # The credential, appended only when absent. Each profile gets its
            # own: the API server reads API_SERVER_KEY from the profile being
            # addressed, so a profile without one 401s on every request.
            if ! grep -q '^API_SERVER_KEY=' "${_dir}/.env" 2>/dev/null; then
                printf 'API_SERVER_KEY=%s\n' "${API_SERVER_KEY:-}" >> "${_dir}/.env"
            fi
        done
    fi
fi

# ── hand off ownership to the hermes user ────────────────────────────────────
# s6-overlay chowns /opt/data on the very first start (using .venv as a
# sentinel to skip on subsequent starts).  Chown our tools explicitly so they
# are accessible after s6 drops to HERMES_UID:HERMES_GID.
HERMES_UID="${HERMES_UID:-1000}"
HERMES_GID="${HERMES_GID:-1000}"
for _owned in "$TOOLS_DIR" "$PROFILES_DIR"; do
    [[ -d "$_owned" ]] && chown -R "${HERMES_UID}:${HERMES_GID}" "$_owned"
done

# ── chain to s6-overlay ───────────────────────────────────────────────────────
# /init is the s6 entrypoint baked into the hermes-agent image.  It runs the
# cont-init scripts (user-remap, chown) and then exec-s the main program under
# HERMES_UID:HERMES_GID.
#
# main-wrapper.sh must sit between /init and "$@": there is no `gateway`
# binary — `gateway` is a *subcommand* of the hermes CLI, and the wrapper is
# what routes "first arg is not an executable" to `hermes <args>`. Chaining
# `exec /init "$@"` skips it, so s6 tried to exec `gateway` directly and the
# container crash-looped on "rc.init: 91: gateway: not found". This mirrors the
# image's own entrypoint-dispatch.sh, which runs /init main-wrapper.sh "$@".
exec /init /opt/hermes/docker/main-wrapper.sh "$@"
