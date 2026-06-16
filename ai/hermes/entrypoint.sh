#!/usr/bin/env bash
# hermes-agent container entrypoint — installs decree and claude-code into the
# persistent data volume, then chains to the image's s6-overlay init (/init)
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

# ── hand off ownership to the hermes user ────────────────────────────────────
# s6-overlay chowns /opt/data on the very first start (using .venv as a
# sentinel to skip on subsequent starts).  Chown our tools explicitly so they
# are accessible after s6 drops to HERMES_UID:HERMES_GID.
HERMES_UID="${HERMES_UID:-1000}"
HERMES_GID="${HERMES_GID:-1000}"
if [[ -d "$TOOLS_DIR" ]]; then
    chown -R "${HERMES_UID}:${HERMES_GID}" "$TOOLS_DIR"
fi

# ── chain to s6-overlay ───────────────────────────────────────────────────────
# /init is the s6 entrypoint baked into the hermes-agent image.  It runs the
# cont-init scripts (user-remap, chown) and then exec-s "$@" (gateway run)
# under HERMES_UID:HERMES_GID.
exec /init "$@"
