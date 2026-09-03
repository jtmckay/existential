#!/usr/bin/env bash
# code-server entrypoint — installs code-server into the persistent cache
# volume on first start, then launches it bound on :8080 behind password auth
# ($PASSWORD, set by Caddy-fronted https://code-server.<domain>). A bare
# shell in this container can read/write the whole workspace and run the
# installed AI CLIs, so it's not just an editor — auth is load-bearing.
set -euo pipefail

INSTALL_PREFIX="/code-server-data"
CODE_SERVER_BIN="$INSTALL_PREFIX/bin/code-server"
USER_DATA_DIR="$INSTALL_PREFIX/user-data"
EXTENSIONS_DIR="$INSTALL_PREFIX/extensions"
SETTINGS_FILE="$USER_DATA_DIR/User/settings.json"
DEFAULT_EXTENSIONS=(
    eamodio.gitlens
    dbaeumer.vscode-eslint
    esbenp.prettier-vscode
    bradlc.vscode-tailwindcss
)

# $HOME (/home/decree, baked in by automations/Dockerfile for the shared
# decree/decree-backup image) is the container's throwaway layer, NOT this
# service's code_server_data volume. Left alone, npm-global installs AND every
# dotfile the AI CLIs write live there: claude-code's account/session state
# (~/.claude.json, ~/.claude/ — confirmed by running `claude config list` in
# this image, which creates both) and opencode's credentials (confirmed via
# `opencode auth list`: "Credentials ~/.local/share/opencode/auth.json"). A
# container recreation (docker compose down/up, an image rebuild,
# `existential.sh reset`) starts from an empty /home/decree, so both CLIs
# reinstall from npm AND the user has to re-authenticate each one — silently,
# since nothing here fails, it just forgets.
#
# Fix by symlinking the specific dirs/file each tool writes into onto the
# volume, in place, rather than moving $HOME or NPM_CONFIG_PREFIX: a login
# shell (code-server's integrated terminal) gets its PATH reset by
# /etc/profile and then rebuilt by the image's /etc/profile.d/npm-global.sh,
# which hardcodes /home/decree/.npm-global/bin — confirmed with
# `bash -l -c 'echo $PATH'` in this image. That file is root-owned (644) and
# this entrypoint runs as the unprivileged host user, so it can't be edited;
# the only way to relocate what it points at without breaking terminal PATH
# is a symlink at the same path.
PERSIST_HOME="$INSTALL_PREFIX/home"
for _dotdir in .npm-global .npm .config .local .cache .claude; do
    # Target must exist as a real dir first: mkdir -p through a dangling
    # symlink fails EEXIST on the symlink itself before it ever reaches the
    # missing target.
    mkdir -p "$PERSIST_HOME/$_dotdir"
    if [[ -e "/home/decree/$_dotdir" && ! -L "/home/decree/$_dotdir" ]]; then
        rm -rf "/home/decree/$_dotdir"
    fi
    [[ -e "/home/decree/$_dotdir" ]] || ln -s "$PERSIST_HOME/$_dotdir" "/home/decree/$_dotdir"
done
if [[ ! -e /home/decree/.claude.json && ! -L /home/decree/.claude.json ]]; then
    ln -s "$PERSIST_HOME/claude.json" /home/decree/.claude.json
fi

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

if ! command -v claude &>/dev/null; then
    echo "[code-server] Installing claude-code..."
    npm i -g @anthropic-ai/claude-code
fi

if ! command -v opencode &>/dev/null; then
    echo "[code-server] Installing opencode-ai..."
    npm i -g opencode-ai
fi

if ! command -v python &>/dev/null; then
    echo "[code-server] Symlinking python -> python3..."
    ln -s "$(command -v python3)" /home/decree/.npm-global/bin/python
fi

WORKSPACE_OPENCODE_JSON="/workspace/opencode.json"
REFERENCE_OPENCODE_JSON="/opencode.exist.json"
if [[ ! -f "$WORKSPACE_OPENCODE_JSON" ]]; then
    echo "[code-server] Copying opencode.json into workspace..."
    cp "$REFERENCE_OPENCODE_JSON" "$WORKSPACE_OPENCODE_JSON"
elif ! cmp -s "$WORKSPACE_OPENCODE_JSON" "$REFERENCE_OPENCODE_JSON"; then
    echo "!!!! WARNING: opencode.json is out of sync with services/code-server/opencode.json. It is only copied into the container on start when it doesn't already exist."
fi

exec "$CODE_SERVER_BIN" \
    --bind-addr 0.0.0.0:8080 \
    --auth password \
    --user-data-dir "$USER_DATA_DIR" \
    --extensions-dir "$EXTENSIONS_DIR" \
    /workspace
