#!/usr/bin/env bash
# POST <PLUGIN_PEER_<FROM>>/plugins/[<machine>/]share/<PLUGIN_SHARE_NAME>, with
# PLUGIN_PEER_<FROM>_TOKEN as its bearer if set (all in automation/.env).
set -euo pipefail
f="${DECREE_DATA_FROM:-}" m="${DECREE_DATA_MACHINE:-}" me="${PLUGIN_SHARE_NAME:-}"
[[ "$f" =~ ^[a-z0-9_-]{1,40}$ ]] || { echo "plugin_request: '${f}' is not a stack name" >&2; exit 1; }
[[ -z "$m" || "$m" =~ ^[a-z][a-z0-9_]{0,40}$ ]] || { echo "plugin_request: '${m}' is not a machine name" >&2; exit 1; }
[[ "$me" =~ ^[a-z0-9_-]{1,40}$ ]] || { echo "plugin_request: set PLUGIN_SHARE_NAME in automation/.env to this stack's name, as ${f} knows it" >&2; exit 1; }
var="PLUGIN_PEER_$(tr 'a-z-' 'A-Z_' <<<"$f")"; tok="${var}_TOKEN"
[[ -n "${!var:-}" ]] || { echo "plugin_request: no ${var} in automation/.env, the address of ${f}'s webhook" >&2; exit 1; }
auth=(); [[ -z "${!tok:-}" ]] || auth=(-H "Authorization: Bearer ${!tok}")
curl -fsS --max-time 30 --retry 3 -X POST "${!var%/}/plugins/${m:+${m}/}share/${me}" "${auth[@]}" >/dev/null
echo "plugin_request: asked ${f} for ${m:-the list of its machines}"
