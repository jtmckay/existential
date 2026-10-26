#!/usr/bin/env bash
# code-server entrypoint — installs code-server into the persistent cache
# volume on first start, then launches it bound on :8080 behind password auth
# ($PASSWORD, set by Caddy-fronted https://code-server.<domain>). A bare
# shell in this container can read/write the whole workspace, reach the hermes
# gateway and run whatever you installed in it, so it's not just an editor —
# auth is load-bearing.
set -euo pipefail

INSTALL_PREFIX="/code-server-data"
CODE_SERVER_BIN="$INSTALL_PREFIX/bin/code-server"
USER_DATA_DIR="$INSTALL_PREFIX/user-data"
EXTENSIONS_DIR="$INSTALL_PREFIX/extensions"
SETTINGS_FILE="$USER_DATA_DIR/User/settings.json"
# From Open VSX (code-server's default gallery), into the volume, so they
# survive recreation. markdown-mermaid draws the ```mermaid diagrams in each
# machine's .decree/graph/<name>.md in the built-in markdown preview.
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

# The two AI CLIs this terminal ships, for a person to drive (machines get
# their own claude in the automation image). Installed into the persisted npm
# prefix, so only the first boot pays for it; `npm i -g <pkg>` in the terminal
# updates either in place.
for _pkg in claude:@anthropic-ai/claude-code opencode:opencode-ai; do
    if [[ ! -x "$NPM_BIN/${_pkg%%:*}" ]]; then
        echo "[code-server] Installing ${_pkg#*:}..."
        npm install -g "${_pkg#*:}"
    fi
done

# opencode's provider is the stack's chat endpoint, resolved by model.sh like
# every other container caller, and its tag. Rewritten every boot so a changed
# EXIST_MODEL_URL* or EXIST_MODEL_CHAT is picked up on recreate; compose points
# OPENCODE_CONFIG here, and opencode merges it under the user's own
# ~/.config/opencode, so a person's settings there still win. share is off:
# opencode sends nothing by default, but /share uploads a session to opncd.ai.
_opencode_config() {
    local url="$1" model="$2" plugin="${3:-}" search="${4:-}"
    jq -n --arg url "$url" --arg model "$model" --arg plugin "$plugin" --arg search "$search" '{
        "$schema": "https://opencode.ai/config.json",
        model: ("existential/" + $model),
        share: "disabled",
        plugin: (if $plugin == "" then [] else [$plugin] end),
        mcp: (if $search == "" then {} else {qmd: {type: "remote", url: $search, enabled: true}} end),
        provider: {existential: {
            name: "existential",
            npm: "@ai-sdk/openai-compatible",
            options: {baseURL: $url},
            models: {($model): {name: $model}}
        }}
    }'
}
# Capture (automation/lib/capture/): what a person types into claude or opencode
# is appended to workspace/.capture/. Claude Code's prompt hook goes into its
# settings.json, opencode's plugin into the config above. Applied every boot, so
# CODE_SERVER_CAPTURE=false plus a recreate is the whole off switch. Never fatal.
_capture_plugin=""
if [[ "${CODE_SERVER_CAPTURE:-true}" != false ]]; then
    bash /opt/capture/capture.sh install /workspace >/dev/null \
        || echo "[code-server] WARN: Claude Code capture hook not installed"
    _capture_plugin="file:///opt/capture/opencode.ts"
else
    bash /opt/capture/capture.sh uninstall >/dev/null \
        || echo "[code-server] WARN: Claude Code capture hook not removed"
fi
# Search (ai/qmd, when EXIST_IS_AI_QMD is true): one index for
# both CLIs. Claude Code gets it at user scope with its read-only tools allowed
# without a prompt, plus the recall skill at the workspace root, which says when
# and how to search; opencode gets it in the config below; the terminal gets a
# `search` command (lib/recall/search.sh, linked like `hermes`). Turning the add-on off
# removes all of it on the next boot. Never fatal: search is optional.
_search=""; [[ "${EXIST_IS_AI_QMD:-false}" == true ]] && _search=http://qmd:8181/mcp
_claude_settings="${CLAUDE_CONFIG_DIR}/settings.json"
{
    "$NPM_BIN/claude" mcp remove qmd --scope user >/dev/null 2>&1 || true
    [[ -s "$_claude_settings" ]] || echo '{}' > "$_claude_settings"
    jq --arg on "${_search:+1}" '.permissions.allow = (((.permissions.allow // []) - ["mcp__qmd"]) + (if $on == "1" then ["mcp__qmd"] else [] end))' \
        "$_claude_settings" > "$_claude_settings.tmp" && mv "$_claude_settings.tmp" "$_claude_settings"
    if [[ -n "$_search" ]]; then
        "$NPM_BIN/claude" mcp add --transport http --scope user qmd "$_search" >/dev/null
        mkdir -p /workspace/.claude/skills/recall
        cp /opt/recall/SKILL.md /workspace/.claude/skills/recall/SKILL.md
        ln -sfn /opt/recall/search.sh "$NPM_BIN/search"
    else
        rm -rf /workspace/.claude/skills/recall "$NPM_BIN/search"
    fi
} || echo "[code-server] WARN: search (ai/qmd) not wired into Claude Code"
# shellcheck source=/dev/null
. /opt/hermes/model.sh
_opencode_config "$(model_url chat)" "${EXIST_MODEL_CHAT:-}" "$_capture_plugin" "$_search" > "$INSTALL_PREFIX/opencode.json"

# `python` for the tools that assume it; the image ships python3 only. PATH
# here is not the login shell's, so ask about python3 rather than testing
# whether `python` already resolves.
if _python3="$(command -v python3)"; then
    ln -sfn "$_python3" "$NPM_BIN/python"
fi

# `hermes "..."` in the integrated terminal, same gateway (and same
# lib/hermes.sh) every decree script uses — see the two read-only mounts in
# docker-compose.exist.yml. A symlink rather than a copy so an edit to
# automation/lib/ is live here on the next invocation. PATH here is the
# npm-global bin dir from /etc/profile.d/npm-global.sh, which is the one
# writable dir already on PATH for a login shell.
if [[ -x /opt/hermes/hermes-cli.sh ]]; then
    ln -sfn /opt/hermes/hermes-cli.sh "$NPM_BIN/hermes"
fi

exec "$CODE_SERVER_BIN" \
    --bind-addr 0.0.0.0:8080 \
    --auth password \
    --disable-telemetry \
    --user-data-dir "$USER_DATA_DIR" \
    --extensions-dir "$EXTENSIONS_DIR" \
    /workspace
