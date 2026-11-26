#!/usr/bin/env bash
# code-server entrypoint — installs code-server into the persistent cache
# volume on first start, then launches it bound on :8080 behind password auth
# ($PASSWORD, set by Caddy-fronted https://code-server.<domain>). A bare
# shell in this container can read/write the whole workspace, reach the
# stack's models and run whatever you installed in it, so it's not just an editor —
# auth is load-bearing.
set -euo pipefail

INSTALL_PREFIX="/code-server-data"
CODE_SERVER_BIN="$INSTALL_PREFIX/bin/code-server"
USER_DATA_DIR="$INSTALL_PREFIX/user-data"
EXTENSIONS_DIR="$INSTALL_PREFIX/extensions"
SETTINGS_FILE="$USER_DATA_DIR/User/settings.json"
# From Open VSX (code-server's default gallery), into the volume, so they
# survive recreation. markdown-mermaid draws the ```mermaid diagrams in each
# machine's .decree/machines/<name>/graph.md in the built-in markdown preview.
DEFAULT_EXTENSIONS=(
    eamodio.gitlens
    dbaeumer.vscode-eslint
    esbenp.prettier-vscode
    bradlc.vscode-tailwindcss
    bierner.markdown-mermaid
)

# $HOME (/home/decree, baked in by automation/Dockerfile for the shared
# decree/decree-backup image) is the container's throwaway layer, NOT this
# service's code_server_data volume. Left alone, every `npm i -g` you run in
# the terminal — and every dotfile the thing you installed writes — lives
# there, and a container recreation (docker compose down/up, an image rebuild,
# `existential.sh reset`) starts from an empty /home/decree: the tool is gone
# AND its login state with it, silently, since nothing here fails.
#
# Fix by symlinking those dotfiles onto the volume, in place, rather than
# moving $HOME or NPM_CONFIG_PREFIX: a login shell (code-server's integrated
# terminal) gets its PATH reset by /etc/profile and then rebuilt by the image's
# /etc/profile.d/npm-global.sh, which hardcodes /home/decree/.npm-global/bin —
# confirmed with `bash -l -c 'echo $PATH'` in this image. That file is
# root-owned (644) and this entrypoint runs as the unprivileged host user, so
# it can't be edited; the only way to relocate what it points at without
# breaking terminal PATH is a symlink at the same path.
#
# The defaults are deliberately generic — npm's global prefix plus the XDG
# dirs, which is where a well-behaved CLI keeps its install and its
# credentials (opencode's login lands in .local/share). Claude Code keeps its
# login in .claude.json, which it replaces by rename, so a symlinked file would
# be clobbered: compose points CLAUDE_CONFIG_DIR at $PERSIST_HOME/.claude
# instead, and both files live there. Any other tool that keeps
# state somewhere else persists too, without a repo edit, because everything
# already in $PERSIST_HOME is linked on every boot. Create it once —
# `mkdir /code-server-data/home/.mytool`, or `touch
# /code-server-data/home/mytool.json` for a dotfile — and it survives from then
# on. Nothing is linked for a name that isn't there yet, so a tool whose state
# lands outside the defaults needs that one-time step before its first login.
PERSIST_HOME="$INSTALL_PREFIX/home"
NPM_BIN="/home/decree/.npm-global/bin"
for _dotdir in .npm-global/bin .npm .config .local .cache .claude; do
    # Target must exist as a real dir first: mkdir -p through a dangling
    # symlink fails EEXIST on the symlink itself before it ever reaches the
    # missing target.
    mkdir -p "$PERSIST_HOME/$_dotdir"
done
shopt -s dotglob nullglob
for _entry in "$PERSIST_HOME"/*; do
    # One leading dot either way, so both `.npm-global` and a bare `tool.json`
    # land at the path $HOME actually uses.
    _link="/home/decree/.$(basename "${_entry}" | sed 's/^\.//')"
    if [[ -e "$_link" && ! -L "$_link" ]]; then
        rm -rf "$_link"
    fi
    ln -sfn "$_entry" "$_link"
done
shopt -u dotglob nullglob

if [[ ! -x "$CODE_SERVER_BIN" ]]; then
    echo "[code-server] Installing code-server (standalone)..."
    curl -fsSL https://code-server.dev/install.sh \
        | sh -s -- --prefix "$INSTALL_PREFIX" --method standalone
fi

if [[ ! -f "$SETTINGS_FILE" ]]; then
    mkdir -p "$(dirname "$SETTINGS_FILE")"
    echo '{"workbench.colorTheme": "Default Dark Modern"}' > "$SETTINGS_FILE"
fi

installed_extensions="$("$CODE_SERVER_BIN" --extensions-dir "$EXTENSIONS_DIR" --list-extensions)"
for extension in "${DEFAULT_EXTENSIONS[@]}"; do
    if ! grep -qix "$extension" <<< "$installed_extensions"; then
        echo "[code-server] Installing extension $extension..."
        "$CODE_SERVER_BIN" --extensions-dir "$EXTENSIONS_DIR" --install-extension "$extension"
    fi
done

# claude, opencode and pi are baked into the image (/usr/local/bin); one you
# `npm i -g` in the terminal lands in the persisted prefix above and wins.

# opencode's provider is the stack's chat endpoint, resolved by model.sh like
# every other container caller, and its tag. Rewritten every boot so a changed
# EXIST_MODEL_URL* or EXIST_MODEL_CHAT is picked up on recreate; compose points
# OPENCODE_CONFIG here, and opencode merges it under the user's own
# ~/.config/opencode, so a person's settings there still win. share is off:
# opencode sends nothing by default, but /share uploads a session to opncd.ai.
_opencode_config() {
    local url="$1" model="$2" key="${3:-}" plugin="${4:-}" mcp="${5:-}"
    [[ -n "$mcp" ]] || mcp='{}'
    jq -n --arg url "$url" --arg model "$model" --arg key "${key:-none}" --arg plugin "$plugin" --argjson mcp "$mcp" '{
        "$schema": "https://opencode.ai/config.json",
        model: ("existential/" + $model),
        share: "disabled",
        plugin: (if $plugin == "" then [] else [$plugin] end),
        mcp: ($mcp | map_values({type: "remote", url: ., enabled: true})),
        provider: {existential: {
            name: "existential",
            npm: "@ai-sdk/openai-compatible",
            options: {baseURL: $url, apiKey: $key},
            models: {($model): {name: $model}}
        }}
    }'
}
# What ./existential.sh installs into the workspace: the model and pi plugins' lib
# (on by default) and capture's (./existential.sh plugin on capture). Without one, what
# needs it is skipped.
_LIB=/workspace/.decree/lib
# Capture (lib/capture/): what a person types into claude or opencode
# is appended to workspace/.capture/. Claude Code's prompt hook goes into its
# settings.json, opencode's plugin into the config above. Applied every boot, so
# CODE_SERVER_CAPTURE=false plus a recreate is the whole off switch. Never fatal.
_capture_plugin=""
if [[ ! -f "${_LIB}/capture/capture.sh" ]]; then
    :   # capture is off until the capture plugin is on
elif [[ "${CODE_SERVER_CAPTURE:-true}" != false ]]; then
    bash "${_LIB}/capture/capture.sh" install /workspace >/dev/null \
        || echo "[code-server] WARN: Claude Code capture hook not installed"
    _capture_plugin="file://${_LIB}/capture/opencode.ts"
else
    bash "${_LIB}/capture/capture.sh" uninstall >/dev/null \
        || echo "[code-server] WARN: Claude Code capture hook not removed"
fi
# The add-ons' MCP servers, for both CLIs: search (ai/qmd) over the workspace and
# the web through firecrawl, each when its add-on is on. Claude Code gets them at
# user scope with their tools allowed without a prompt, plus the recall skill at
# the workspace root, which says when and how to search; opencode gets them in its
# config; the terminal gets a `search` command (ai/qmd/recall/search.sh). An
# add-on turned off is removed on the next boot. Never fatal.
_mcp='{}'
[[ "${EXIST_IS_AI_QMD:-false}" == true ]] && _mcp="$(jq -c '. + {qmd: "http://qmd:8181/mcp"}' <<<"$_mcp")"
[[ "${EXIST_IS_AI_FIRECRAWL:-false}" == true ]] && _mcp="$(jq -c '. + {firecrawl: "http://firecrawl-mcp:3003/mcp"}' <<<"$_mcp")"
_claude_settings="${CLAUDE_CONFIG_DIR}/settings.json"
{
    [[ -s "$_claude_settings" ]] || echo '{}' > "$_claude_settings"
    for _name in qmd firecrawl; do
        claude mcp remove "$_name" --scope user >/dev/null 2>&1 || true
        _url="$(jq -r --arg n "$_name" '.[$n] // empty' <<<"$_mcp")"
        [[ -z "$_url" ]] || claude mcp add --transport http --scope user "$_name" "$_url" >/dev/null
    done
    jq --argjson mcp "$_mcp" '.permissions.allow = (((.permissions.allow // []) - ["mcp__qmd", "mcp__firecrawl"]) + ($mcp | keys | map("mcp__" + .)))' \
        "$_claude_settings" > "$_claude_settings.tmp" && mv "$_claude_settings.tmp" "$_claude_settings"
    if [[ "${EXIST_IS_AI_QMD:-false}" == true ]]; then
        mkdir -p /workspace/.claude/skills/recall
        cp /opt/recall/SKILL.md /workspace/.claude/skills/recall/SKILL.md
        ln -sfn /opt/recall/search.sh "$NPM_BIN/search"
    else
        rm -rf /workspace/.claude/skills/recall "$NPM_BIN/search"
    fi
} || echo "[code-server] WARN: MCP servers (qmd, firecrawl) not wired into Claude Code"
if [[ ! -f "${_LIB}/model.sh" ]]; then
    echo "[code-server] WARN: no model lib in the workspace (is automation on?), so opencode is not configured"
else
    # shellcheck source=/dev/null
    . "${_LIB}/model.sh"
    if [[ -z "$(model_url)" ]]; then
        rm -f "$INSTALL_PREFIX/opencode.json"
        echo "[code-server] no model yet: set EXIST_MODEL_URL (and EXIST_MODEL_KEY) in .env.shared for opencode and pi"
    else
        _opencode_config "$(model_url)" "$(model_tag chat)" "$(model_key)" "$_capture_plugin" "$_mcp" > "$INSTALL_PREFIX/opencode.json"
    fi
fi

# `python` for the tools that assume it; the image ships python3 only. PATH
# here is not the login shell's, so ask about python3 rather than testing
# whether `python` already resolves.
if _python3="$(command -v python3)"; then
    ln -sfn "$_python3" "$NPM_BIN/python"
fi

# pi is baked into the image; its provider and MCP servers are the ones
# automation's pi gets, from the same lib/pi.sh. Never fatal.
# shellcheck source=/dev/null
( . "${_LIB}/pi.sh" && pi_configure ) || echo "[code-server] WARN: pi not configured (is the pi plugin installed?)"

exec "$CODE_SERVER_BIN" \
    --bind-addr 0.0.0.0:8080 \
    --auth password \
    --disable-telemetry \
    --user-data-dir "$USER_DATA_DIR" \
    --extensions-dir "$EXTENSIONS_DIR" \
    /workspace
