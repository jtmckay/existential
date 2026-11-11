#!/usr/bin/env bash
# The machine as a plugin file (lib/automations/plugin.sh), or with no machine the
# list of them, each free or asking, POSTed to the client's PLUGIN_SHARE_CALLBACK_<CLIENT>,
# with PLUGIN_SHARE_CALLBACK_<CLIENT>_TOKEN as its bearer if set.
set -euo pipefail
source "${DECREE_LIB}/automations/registry.sh"
source "${DECREE_LIB}/automations/plugin.sh"
var="PLUGIN_SHARE_CALLBACK_$(tr 'a-z-' 'A-Z_' <<<"$DECREE_DATA_CLIENT")"; tok="${var}_TOKEN"
m="${DECREE_DATA_MACHINE:-}"
file="${DECREE_RUN_DIR}/${m:-machines}.md"
if [[ -n "$m" ]]; then
    plugin_export "$m" > "$file"
else
    allow=" $(tr ',' ' ' <<<"${PLUGIN_SHARE_ALLOW:-}") "
    { printf -- '---\ncatalog: true\n---\n'
      for f in .decree/machines/*.yml; do
          n="$(basename "$f" .yml)"; how=asks; [[ "$allow" != *" ${n} "* ]] || how=free
          printf -- '- %s (%s): %s\n' "$n" "$how" "$(yq -r '.description // ""' "$f")"
      done; } > "$file"
fi
auth=(); [[ -z "${!tok:-}" ]] || auth=(-H "Authorization: Bearer ${!tok}")
curl -fsS --max-time 30 --retry 3 -X POST "${!var}" -H 'Content-Type: text/markdown' "${auth[@]}" \
    --data-binary @"$file" >/dev/null
echo "plugin_share: sent ${m:-the list of machines} to ${DECREE_DATA_CLIENT}"
