---
name: plugin_offer
x-exist-project: automation
needs:
  - plugin_request
machine:
  description: Another stack offers a machine as a plugin file, which waits in ai/proposed/ until you move it into .decree/plugins/ and install it, or sends the list of its machines, which goes to your phone.
  data:
    from: {type: string, default: ""}
  initial: offer
  states:
    offer:
      invoke: offer
      transitions: {done: done}
      emits: [notify]
    done: {final: true}
    failed: {final: true}
scripts:
  offer.sh: |
    #!/usr/bin/env bash
    # The body is a plugin file. Once it reads as one, it is written to
    # ai/proposed/<name>.md and you are told; nothing is installed until you move it
    # into .decree/plugins/ and `decree install <name>`.
    # A list of machines (catalog: true) is only sent to your phone.
    set -euo pipefail
    # shellcheck source=../../lib/plugin.sh
    source ".decree/lib/plugin.sh"
    WS="${AUTOMATIONS_WORKSPACE:-/workspace}"
    from="${DECREE_DATA_FROM:-}"
    file="${DECREE_RUN_DIR}/offer.md"
    body() { awk 'NR==1 && /^---$/{f=1; next} f && /^---$/{f=0; next} !f' "$1" | sed '/./,$!d'; }
    body "$DECREE_MESSAGE" > "$file"
    fm() { yq --front-matter=extract -r "$1" "$file" 2>/dev/null || true; }
    if [[ "$(fm '.catalog // false')" == true ]]; then
        { printf '%s has these machines. A free one is sent at once; one that asks waits for their yes.\n\n' "${from:-Another stack}"
          body "$file"
          printf '\nAsk for one:  echo | docker exec -i automation decree emit --machine plugin_request --param from=%s --param machine=<name>\n' "${from:-<from>}"
        } | "${DECREE:-decree}" emit --machine notify --param ntfy_topic=suggestions --param ntfy_title="Machines ${from:-a stack} shares" --param ntfy_tags=package >/dev/null
        echo "plugin_offer: sent ${from:-their} list of machines to your phone"; exit 0
    fi
    name="$(fm '.name // ""')"
    [[ "$name" =~ ^[a-z][a-z0-9_]{2,40}$ ]] && plugin_is "$file" ||
        { echo "plugin_offer: what ${DECREE_DATA_FROM:-it} sent is not a plugin file" >&2; exit 1; }
    out="${WS}/ai/proposed/${name}.md"
    mkdir -p "$(dirname "$out")"
    cp "$file" "${out}.tmp" && mv "${out}.tmp" "$out"
    echo "plugin_offer: wrote ai/proposed/${name}.md"
    if [[ -e ".decree/machines/${name}/machine.yml" ]]; then had=" It would replace the ${name} you have."; else had=""; fi
    { printf '%s offers the machine %s.%s\n\n' "${DECREE_DATA_FROM:-Another stack}" "$name" "$had"; plugin_offered "$name"; } |
        "${DECREE:-decree}" emit --machine notify --param ntfy_topic=suggestions --param ntfy_title="A machine offered to you" --param ntfy_tags=package >/dev/null
x-exist-endpoints:
  - path: /plugins/offer/{from}
    patterns: {from: "[a-z0-9_-]{1,40}"}
    body: required
    message:
      machine: plugin_offer
      params: {from: "{{from}}"}
---
# plugin_offer

Another stack offers a machine as a plugin file, which waits in ai/proposed/ until you move it into .decree/plugins/ and install it, or sends the list of its machines, which goes to your phone.
