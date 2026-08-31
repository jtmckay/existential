#!/usr/bin/env bash
# homeassistant — make the reverse-proxy settings actually get SERVED.
#
# HA answers every proxied request with a bare 400 unless http.use_x_forwarded_for
# and http.trusted_proxies are in effect, so https://homeassistant.<domain> is
# broken for browsers while direct access on :8123 keeps working. That split is
# what makes it easy to miss.
#
# The setting lives in TWO places and only one of them counts. HA 2026.8 moved
# http config out of YAML into .storage/http, and serves `data.stable` — nothing
# else. It reads configuration.yaml exactly once, stages the result in
# `data.pending` with "error": "not_promoted", and never promotes it. Restarting
# does not promote it either (verified). So the YAML block alone is not enough,
# no matter how correct it looks, and `check_config` still calls it valid.
#
# Writing `stable` is therefore the only fix, and it has to happen while HA is
# NOT running — HA rewrites .storage on shutdown, so an edit made against a live
# instance is discarded. That is precisely what an entrypoint can do and a
# pre-startup host script cannot: here we are root, we own /config, and we run in
# the window before HA starts.
#
# Ordering, and why one restart can be needed:
#
#   - .storage/http already exists  → patch it now, before exec'ing HA. Done.
#   - it does not exist yet (a first-ever boot) → HA has to create it first.
#     Wait for that in the background, and if `stable` is still unserved, signal
#     PID 1 so the container exits cleanly and docker's `restart: unless-stopped`
#     brings it straight back. The next start takes the branch above and fixes it.
#
# That bounds the restart to one: it is only ever requested on a boot that began
# with no .storage/http, and after the restart there is one.
#
# Values come from `pending` first — that is HA's own read of configuration.yaml,
# so a trusted_proxies the user tuned there wins — then whatever `stable` already
# had, then HOMEASSISTANT_TRUSTED_PROXIES. Nothing deliberate is clobbered.
set -euo pipefail

STORE=/config/.storage/http
SUBNET="${HOMEASSISTANT_TRUSTED_PROXIES:-172.16.0.0/12}"

# "ok" when stable serves the settings and nothing is staged behind it.
# Schema v1 (no "stable" key) has no promotion step and needs only the migration
# flag cleared, which is all that schema ever needed.
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

_state() { jq -r "$_JQ_CHECK" "$STORE" 2>/dev/null || echo unknown; }

# Rewrite THROUGH the existing file so it keeps HA's ownership and mode, and only
# once jq has produced something — a failed filter must not truncate the store.
_patch() {
    local new
    new="$(jq --arg subnet "$SUBNET" "$_JQ_FIX" "$STORE" 2>/dev/null)" || return 1
    [ -n "$new" ] || return 1
    printf '%s\n' "$new" > "$STORE" || return 1
}

_had_store=false
[ -f "$STORE" ] && _had_store=true

if [ "$_had_store" = true ] && [ "$(_state)" = fix ]; then
    if _patch; then
        echo "[homeassistant] applied http.trusted_proxies (${SUBNET}) — proxied access enabled."
    else
        echo "[homeassistant] WARNING: could not write ${STORE}; proxied requests will answer 400." >&2
    fi
fi

# First-ever boot: HA has not written .storage/http yet, so there is nothing to
# patch until it has. Watch for it, then ask for the single restart described
# above. Backgrounded so HA still comes up as PID 1 under s6.
if [ "$_had_store" = false ]; then
    (
        _waited=0
        while [ ! -f "$STORE" ]; do
            [ "$_waited" -ge 300 ] && exit 0      # HA never got there; nothing to do
            sleep 2; _waited=$(( _waited + 2 ))
        done
        sleep 5                                   # let HA finish writing it
        [ "$(_state)" = fix ] || exit 0
        echo "[homeassistant] proxy settings staged but not served — restarting once to apply."
        kill -TERM 1                              # clean s6 shutdown; docker restarts us
    ) &
fi

exec /init "$@"
