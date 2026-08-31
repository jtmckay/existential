#!/usr/bin/env bash
# exist.initial.sh — pre-startup setup for homeassistant.
#
# Home Assistant generates /config/configuration.yaml itself on first run, and
# that generated file has no `http:` section. Without one, HA rejects every
# request arriving through a reverse proxy with a bare "400 Bad Request" — so
# https://homeassistant.<domain> is broken for browsers, while direct
# container-to-container access on :8123 keeps working. That split is what makes
# it easy to miss.
#
# Two things are needed, because HA 2026.8 moved http config out of YAML, and
# this script owns only the first:
#
#   1. The `http:` block in configuration.yaml — here. It is the file the user
#      edits, so trusted_proxies is tuned there and everything downstream reads
#      it back.
#   2. The same settings in `.storage/http`'s `data.stable`, the only place HA
#      actually serves from — services/homeassistant/entrypoint.sh. HA stages the
#      YAML into `data.pending` with "error": "not_promoted" and never promotes
#      it, not even across a restart, so `stable` has to be written directly and
#      only while HA is stopped. This script has no such window: on a first
#      install HA has not created the file yet, and afterwards HA is running and
#      would discard the edit on shutdown. The entrypoint runs in exactly that
#      gap, as root, inside the container.
#
# Seeding matters for the same reason. HA writes configuration.yaml on its own
# first start, so a pre-startup script that waits for the file never gets to add
# the block on a fresh install. HA never overwrites an existing
# configuration.yaml, so this writes it first instead.
#
# Idempotent, and silent once the block is present.
#
# See .claude/reference/services.md for the convention.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CONFIG_DIR="${REPO_DIR}/volumes/homeassistant_data"
CONFIG="${CONFIG_DIR}/configuration.yaml"

# Whether the YAML block is already present. This gates ONLY step 1 — an
# early `exit 0` here (the original shape) skipped the storage repair too, so an
# install whose configuration.yaml already had the block could never get the
# migration cleared or the pending config promoted: the file looked right, HA
# kept answering 400, and nothing in the render said otherwise. Step 2 has to run
# on every invocation precisely BECAUSE the block is present.
HAVE_BLOCK=false
grep -qE '^http:' "$CONFIG" 2>/dev/null && HAVE_BLOCK=true

# The docker bridge caddy sits on. Trusting the network rather than a pinned
# container IP keeps this correct when caddy is recreated and its address moves.
SUBNET="${EXIST_DOCKER_SUBNET:-172.16.0.0/12}"

_http_block() {
    cat <<EOF

# Added by exist.initial.sh — required for access through the caddy reverse
# proxy. Without it HA answers proxied requests with 400. Adjust trusted_proxies
# if your docker bridge uses a different range.
http:
  use_x_forwarded_for: true
  trusted_proxies:
    - ${SUBNET}
EOF
}

# Seed the config before HA's first start.
#
# HA generates configuration.yaml itself on first run and the generated file has
# no `http:` section, so a fresh install answers 400 to every proxied request —
# and this script, running pre-startup, used to have no file to fix and exited.
# The block only landed on a LATER render, which is why a first install looked
# like it needed a second pass. HA never overwrites an existing
# configuration.yaml, so writing it here makes this a genuine pre-startup step.
#
# Content mirrors HA's own default. The three !include targets are created
# alongside it because HA errors on a missing include, and its UI automation,
# script and scene editors write to exactly those files.
_seed_config() {
    mkdir -p "$CONFIG_DIR"
    [ -f "${CONFIG_DIR}/automations.yaml" ] || printf '[]\n' > "${CONFIG_DIR}/automations.yaml"
    [ -f "${CONFIG_DIR}/scripts.yaml" ]     || printf '{}\n' > "${CONFIG_DIR}/scripts.yaml"
    [ -f "${CONFIG_DIR}/scenes.yaml" ]      || printf '[]\n' > "${CONFIG_DIR}/scenes.yaml"
    cat > "$CONFIG" <<'YAML'
# Loads default set of integrations. Do not remove.
default_config:

automation: !include automations.yaml
script: !include scripts.yaml
scene: !include scenes.yaml
YAML
    _http_block >> "$CONFIG"
    echo "  homeassistant: seeded configuration.yaml with http.trusted_proxies (${SUBNET})"
}

# Fresh install: nothing has started yet, so there is no .storage to repair
# either — seeding is the whole job.
if [ ! -f "$CONFIG" ]; then
    if [ -w "$CONFIG_DIR" ] || mkdir -p "$CONFIG_DIR" 2>/dev/null; then
        _seed_config
        exit 0
    fi
    echo "  homeassistant: NOTE — cannot create ${CONFIG_DIR#"${REPO_DIR}/"} as $(id -un), so the"
    echo "                 http: block needed for proxied access was not seeded."
    exit 0
fi

# HA runs as root, so on an install it has already started, configuration.yaml is
# root-owned and cannot be written in place by the host user. The directory it
# sits in is ours, though, so append via copy-and-replace: same content, no sudo,
# no prompt in the middle of a render. Ownership moves to the host user, which
# HA (running as root) is unaffected by.
if [ "$HAVE_BLOCK" = true ]; then
    :   # step 1 already done (by us or by the user) — fall through to step 2
elif [ -w "$CONFIG" ]; then
    _http_block >> "$CONFIG"
elif [ -w "$CONFIG_DIR" ]; then
    _tmp="${CONFIG}.exist.$$"
    cp -p "$CONFIG" "$_tmp"
    _http_block >> "$_tmp"
    mv -f "$_tmp" "$CONFIG"
else
    echo "  homeassistant: NOTE — cannot write configuration.yaml or its directory as"
    echo "                 $(id -un), so the http: block needed for proxied access was"
    echo "                 not added. https://homeassistant.<domain> will answer 400."
    exit 0
fi

[ "$HAVE_BLOCK" = true ] || echo "  homeassistant: added http.trusted_proxies (${SUBNET}) to configuration.yaml"

# The .storage/http half of this is NOT here. HA serves data.stable and nothing
# else, and it rewrites .storage on shutdown — so those values can only be
# written while HA is stopped, which is a window this script does not have (on a
# first install HA has not even created the file yet). services/homeassistant/
# entrypoint.sh does it instead: it runs as root inside the container, in the gap
# before HA starts, and restarts once if the file did not exist yet. That is why
# this script no longer needs a container runtime, jq, or the old "stop HA and
# re-run" advice.
