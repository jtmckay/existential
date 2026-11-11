#!/usr/bin/env bash
# The client has a callback and the machine exists. No machine asks for the list,
# and that, or a machine listed in PLUGIN_SHARE_ALLOW (automation/.env, space or
# comma separated), needs no yes.
set -euo pipefail
m="${DECREE_DATA_MACHINE:-}" c="${DECREE_DATA_CLIENT:-}"
[[ "$c" =~ ^[a-z0-9_-]{1,40}$ ]] || { echo "plugin_share: '${c}' is not a client name" >&2; exit 1; }
var="PLUGIN_SHARE_CALLBACK_$(tr 'a-z-' 'A-Z_' <<<"$c")"
[[ -n "${!var:-}" ]] || { echo "plugin_share: no ${var} in automation/.env, so nothing can be sent to ${c}" >&2; exit 1; }
if [[ -z "$m" ]]; then echo allowed > "$DECREE_EVENT_FILE"; exit 0; fi
[[ "$m" =~ ^[a-z][a-z0-9_]{0,40}$ && -f ".decree/machines/${m}.yml" ]] || { echo "plugin_share: there is no machine '${m}'" >&2; exit 1; }
if [[ " $(tr ',' ' ' <<<"${PLUGIN_SHARE_ALLOW:-}") " == *" ${m} "* ]]; then
    echo allowed > "$DECREE_EVENT_FILE"
else
    echo "plugin_share: ${m} is not in PLUGIN_SHARE_ALLOW, so you are asked"
fi
