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
# Two things are needed, because HA 2026.8 moved http config out of YAML:
#
#   1. The `http:` block in configuration.yaml.
#   2. The same settings in `.storage/http`'s `data.stable` — the only place HA
#      actually serves from. HA migrates the YAML http section into storage
#      exactly once and then sets "yaml_migration_done": true, after which the
#      YAML section is ignored, so an install that migrated before this block
#      existed keeps rejecting proxied requests no matter what
#      configuration.yaml says — and `check_config` still reports the setting as
#      valid, which makes it look applied when it is not.
#
#      Clearing yaml_migration_done does NOT fix that on schema v2 (HA 2026.8+),
#      which splits the file into "stable" and "pending": the re-read lands in
#      "pending" with "error": "not_promoted", "stable" keeps the old values, and
#      HA sets the flag straight back to true. That is a loop, not a fix, and it
#      is what this script used to advise. Step 2 now writes `stable` directly.
#
# Both steps are idempotent, and step 2 is silent once `stable` is correct — it
# steers by the served config, not by the migration flag, so it has a terminating
# condition. Step 1 works even after HA has started and taken root ownership of
# /config (see the write below); step 2 cannot write as the host user at all,
# because .storage/http is 0600 root:root, so it does its edit as root inside a
# throwaway container. If neither is possible it prints instructions and exits 0
# — failing would abort every later service's initial script.
#
# See .claude/reference/services.md for the convention.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CONFIG_DIR="${REPO_DIR}/volumes/homeassistant_data"
CONFIG="${CONFIG_DIR}/configuration.yaml"
HTTP_STORE="${CONFIG_DIR}/.storage/http"

# Nothing to do before HA's own first run has created the file.
[ -f "$CONFIG" ] || exit 0

# Whether the YAML block is already present. This gates ONLY step 1 — an
# early `exit 0` here (the original shape) skipped the storage repair too, so an
# install whose configuration.yaml already had the block could never get the
# migration cleared or the pending config promoted: the file looked right, HA
# kept answering 400, and nothing in the render said otherwise. Step 2 has to run
# on every invocation precisely BECAUSE the block is present.
HAVE_BLOCK=false
grep -qE '^http:' "$CONFIG" && HAVE_BLOCK=true

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

# Fresh install: no .storage/http yet, so HA's first migration will read the
# block we just wrote and there is nothing to clear.
[ -f "$HTTP_STORE" ] || exit 0

# ── Step 2: make .storage/http actually serve the proxy settings ──────────────
#
# The target is `data.stable` — the only thing HA serves from. Everything else
# (`yaml_migration_done`, `pending`) is machinery around getting values there,
# and steering by it is what made the old version of this script loop forever:
# clearing yaml_migration_done makes HA re-read the YAML, but HA then stages the
# result in `pending` with "error": "not_promoted" and sets the flag back to
# true — so the next render saw `true` again, printed the same advice again, and
# the proxy kept answering 400 no matter how many times the user followed it.
# We write the values straight into `stable` instead, which converges in one
# pass and is a genuine no-op once it has.
#
# Access: HA runs as root and .storage/http is 0600 root:root, so the host user
# usually cannot even read it. Rather than asking for sudo (this script must
# stay non-interactive), we borrow the container runtime — the same one that is
# about to start the stack — and do the edit as root inside a throwaway
# container. `existential/decree:local` is guaranteed present: existential.sh
# builds it before anything else runs, and it ships jq.
#
# Writes go THROUGH the existing file (`> /s/http`), never via mv, so the file
# keeps HA's ownership and mode.

# Whichever runtime is present; existential.sh has already errored out if neither is.
RUNTIME=""
command -v docker >/dev/null 2>&1 && RUNTIME=docker
[ -n "$RUNTIME" ] || { command -v podman >/dev/null 2>&1 && RUNTIME=podman; }

# One jq program, two uses. `check` prints "ok" when stable already serves the
# settings and nothing is staged behind it; `fix` writes them in.
#
# Values come from pending first (a re-read of the user's YAML, so it reflects
# any trusted_proxies they tuned), then whatever stable already had, then our
# subnet — so this never clobbers a deliberate choice. Schema v1 (no "stable"
# key) has no promotion step: there we fall back to clearing the migration flag,
# which is all that schema ever needed.
_JQ_CHECK='
  if (.data | has("stable")) then
    (.data.stable.use_x_forwarded_for == true)
    and ((.data.stable.trusted_proxies // []) | length > 0)
    and ((.data.pending // null) == null)
  else
    (.data.yaml_migration_done != true)
  end | if . then "ok" else "fix" end'

_JQ_FIX='
  if (.data | has("stable")) then
      .data.stable = ((.data.stable // {}) + {
          use_x_forwarded_for: (.data.pending.use_x_forwarded_for
                                // .data.stable.use_x_forwarded_for // true),
          trusted_proxies:     (.data.pending.trusted_proxies
                                // .data.stable.trusted_proxies // [$subnet]),
          error: null, error_message: null })
    | .data.pending = null
    | .data.yaml_migration_done = true
  else
    .data.yaml_migration_done = false
  end'

# _http_store <check|fix> — run the program against .storage/http, on the host
# when we can write it, otherwise as root inside a container. Echoes "ok"/"fix"
# for check; echoes nothing for fix. Non-zero means we could not get at the file.
_http_store() {
    local mode="$1"
    if [ -w "$HTTP_STORE" ]; then
        case "$mode" in
            check) jq -r "$_JQ_CHECK" "$HTTP_STORE" ;;
            fix)   local _new
                   _new="$(jq --arg subnet "$SUBNET" "$_JQ_FIX" "$HTTP_STORE")" || return 1
                   [ -n "$_new" ] || return 1
                   printf '%s\n' "$_new" > "$HTTP_STORE" ;;
        esac
        return 0
    fi
    [ -n "$RUNTIME" ] || return 1
    case "$mode" in
        check) $RUNTIME run --rm --user 0:0 -v "${CONFIG_DIR}/.storage:/s:ro" \
                   --entrypoint jq existential/decree:local -r "$_JQ_CHECK" /s/http 2>/dev/null ;;
        fix)   $RUNTIME run --rm --user 0:0 -v "${CONFIG_DIR}/.storage:/s" \
                   -e SUBNET="$SUBNET" --entrypoint sh existential/decree:local -c \
                   'new="$(jq --arg subnet "$SUBNET" "$0" /s/http)" || exit 1
                    [ -n "$new" ] || exit 1
                    printf "%s\n" "$new" > /s/http' "$_JQ_FIX" >/dev/null 2>&1 ;;
    esac
}

# jq is needed on both paths: on the host path directly, and to build the
# container arguments meaningfully. Say so rather than skipping in silence —
# without this half of the fix the proxy keeps answering 400 and nothing
# explains why.
if [ -w "$HTTP_STORE" ] && ! command -v jq >/dev/null 2>&1; then
    echo "  homeassistant: NOTE — jq not found, so the staged http config could not be"
    echo "                 promoted. Install jq and re-run ./existential.sh if"
    echo "                 https://homeassistant.<domain> still answers 400."
    exit 0
fi

_state="$(_http_store check 2>/dev/null || true)"

# Already serving the settings — the common case after the first repair, and the
# whole point of steering by `stable`: silence, every render, forever.
[ "$_state" = "ok" ] && exit 0

if [ "$_state" != "fix" ]; then
    echo "  homeassistant: NOTE — .storage/http is not readable by $(id -un) and no"
    echo "                 container runtime is available to read it as root, so the"
    echo "                 http settings could not be verified. If"
    echo "                 https://homeassistant.<domain> answers 400, run"
    echo "                 ./existential.sh again once docker is available."
    exit 0
fi

# HA rewrites .storage on shutdown, so an edit made while it is running is
# discarded the moment the stack goes down. Ask for a stop rather than doing
# work that will silently vanish. This note ends the moment they do it.
if [ -n "$RUNTIME" ] && [ "$($RUNTIME inspect -f '{{.State.Running}}' homeassistant 2>/dev/null)" = "true" ]; then
    echo "  homeassistant: NOTE — the http: block is not in effect, so proxied requests"
    echo "                 answer 400. The repair needs HA stopped (it rewrites"
    echo "                 .storage on shutdown). Run:"
    echo "                     docker compose stop homeassistant && ./existential.sh"
    echo "                     docker compose up -d"
    exit 0
fi

if _http_store fix; then
    echo "  homeassistant: wrote http.trusted_proxies (${SUBNET}) into the active config"
else
    echo "  homeassistant: NOTE — could not update .storage/http, so proxied requests will"
    echo "                 answer 400. With the stack down, run:"
    echo "                     sudo ${RUNTIME:-docker} run --rm -v ${CONFIG_DIR}/.storage:/s \\"
    echo "                       --entrypoint sh existential/decree:local -c 'jq \"...\" /s/http'"
    echo "                 or make ${HTTP_STORE} writable and re-run ./existential.sh."
fi
