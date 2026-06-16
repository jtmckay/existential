#!/usr/bin/env bash
# code-server entrypoint — installs code-server into the persistent cache
# volume on first start, then launches it bound on :8080 behind password auth
# ($PASSWORD, set by Caddy-fronted https://code-server.internal). A bare
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
