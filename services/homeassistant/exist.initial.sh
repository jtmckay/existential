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
#   2. A re-read of it, AND a promotion. HA migrates the YAML http section into
#      .storage/http exactly once and then sets "yaml_migration_done": true,
#      after which the YAML section is ignored. An install that migrated before
#      this block existed therefore keeps rejecting proxied requests no matter
#      what configuration.yaml says — and `check_config` still reports the
#      setting as valid, which makes it look applied when it is not. Clearing
#      the flag makes HA read the section again.
#
#      Storage schema v2 (HA 2026.8+) then splits .storage/http into "stable"
#      and "pending". A re-read lands the settings in "pending" with
#      "error": "not_promoted" while "stable" — the config actually serving —
#      keeps the old values, so clearing the flag ALONE still leaves the proxy
#      returning 400. The keys must be copied into "stable" and "pending" set
#      to null. This is the schema-v2 half of the same fix; on the older
#      single-blob schema there is no "stable" key and the copy is a no-op.
#
# Both steps are idempotent. Step 1 only acts when the block is absent, so a user
# who has tuned their own trusted_proxies keeps it; step 2 runs every time,
# because the case it repairs is exactly the one where step 1 has nothing to do. Step 1 works even after HA has
# started and taken root ownership of /config (see the write below); step 2
# cannot, because .storage is a root-owned directory, so it prints instructions
# and exits 0 — failing would abort every later service's initial script.
#
# See .claude/reference/services.md for the convention.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CONFIG_DIR="${REPO_DIR}/volumes_local/homeassistant_config"
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

# HA writes .storage as root with mode 0600, so the host user usually cannot
# touch it. Say so plainly rather than failing the whole render.
if [ ! -w "$HTTP_STORE" ]; then
    echo "  homeassistant: NOTE — .storage/http is not writable by $(id -un); HA will keep"
    echo "                 ignoring the new http: block. With the stack down, run:"
    echo "                 sudo sed -i 's/\"yaml_migration_done\": true/\"yaml_migration_done\": false/' \\"
    echo "                   ${HTTP_STORE}"
    exit 0
fi

if grep -q '"yaml_migration_done": *true' "$HTTP_STORE" 2>/dev/null; then
    sed -i 's/"yaml_migration_done": *true/"yaml_migration_done": false/' "$HTTP_STORE"
    echo "  homeassistant: cleared yaml_migration_done so HA re-reads the http: block"
fi

# Schema v2: promote anything already staged in "pending" into "stable", so the
# re-read above is not silently parked behind "error": "not_promoted". No-op on
# the old single-blob schema (no "stable" key) and on a file with nothing
# pending. jq is a host tool here — this script runs on the host, not in the
# adhoc container — so say so rather than skipping in silence: without this half
# of the fix the proxy keeps answering 400 and nothing explains why.
if ! command -v jq >/dev/null 2>&1; then
    echo "  homeassistant: NOTE — jq not found, so the staged http config could not be"
    echo "                 promoted. Install jq and re-run ./existential.sh if"
    echo "                 https://homeassistant.<domain> still answers 400."
    exit 0
fi

# Which of our keys are actually sitting in "pending". Empty means old schema,
# nothing staged, or a file jq could not parse — all no-ops.
_moved="$(jq -r '
    if (.data | type) == "object" and (.data | has("stable"))
    then [ (.data.pending // {}) | keys_unsorted[]
           | select(. == "use_x_forwarded_for" or . == "trusted_proxies") ] | join(", ")
    else "" end
' "$HTTP_STORE" 2>/dev/null || true)"

[ -n "$_moved" ] || exit 0

# Write through the existing file rather than mv-ing a temp over it: .storage/http
# is HA's, and a replace would hand it our ownership and mode.
_promoted="$(jq '
    .data.stable = ((.data.stable // {})
                    + ((.data.pending // {})
                       | with_entries(select(.key == "use_x_forwarded_for"
                                          or .key == "trusted_proxies")))
                    + {error: null, error_message: null})
  | .data.pending = null
' "$HTTP_STORE" 2>/dev/null)" || exit 0

[ -n "$_promoted" ] || exit 0

printf '%s\n' "$_promoted" > "$HTTP_STORE"
echo "  homeassistant: promoted ${_moved} into the active http config"
