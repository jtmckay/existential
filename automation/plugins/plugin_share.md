---
name: plugin_share
x-exist-project: automation
machine:
  description: Send one of this stack's machines, as a plugin file, to a client that asked for it, once it is shared freely or you say yes; or, asked for none, the list of them.
  data:
    machine: {type: string, default: ""}
    client: {type: string, default: ""}
  initial: permit
  states:
    permit:
      # The list, or a machine in PLUGIN_SHARE_ALLOW, goes straight out; any other asks you.
      invoke: permit
      transitions: {allowed: send, done: ask}
    ask:
      # asked tells you who wants which machine; a day without an answer is a no.
      invoke:
        reply:
          question: Send this machine to the stack that asked for it?
          notify: asked
          timeout: 24h
      transitions:
        share: {target: send, description: "Send it."}
        refuse: {target: done, description: "Send nothing."}
        error: done
      emits: [notify]
    send:
      invoke: send
      transitions: {done: done}
    done: {final: true}
    failed: {final: true}
scripts:
  asked.sh: |
    #!/usr/bin/env bash
    # One message naming who asks for what, and how to answer.
    set -euo pipefail
    printf '%s asks for the machine %s.\n\nSend it:  docker exec automation decree reply %s share\nRefuse:   docker exec automation decree reply %s refuse\n\nUnanswered, it is refused in a day.\n' \
        "$DECREE_DATA_CLIENT" "$DECREE_DATA_MACHINE" "$DECREE_WAIT_ID" "$DECREE_WAIT_ID" |
        "${DECREE:-decree}" emit --machine notify --param ntfy_title="A stack asks for a machine" --param ntfy_tags=package >/dev/null
    echo "plugin_share: ${DECREE_DATA_CLIENT} asks for the machine ${DECREE_DATA_MACHINE}"
  permit.sh: |
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
    [[ "$m" =~ ^[a-z][a-z0-9_]{0,40}$ && -f ".decree/machines/${m}/machine.yml" ]] || { echo "plugin_share: there is no machine '${m}'" >&2; exit 1; }
    if [[ " $(tr ',' ' ' <<<"${PLUGIN_SHARE_ALLOW:-}") " == *" ${m} "* ]]; then
        echo allowed > "$DECREE_EVENT_FILE"
    else
        echo "plugin_share: ${m} is not in PLUGIN_SHARE_ALLOW, so you are asked"
    fi
  send.sh: |
    #!/usr/bin/env bash
    # The machine's plugin file, the one it was installed from (.decree/plugins/), or
    # with no machine the list of them, each free or asking, POSTed to the client's
    # PLUGIN_SHARE_CALLBACK_<CLIENT>, with PLUGIN_SHARE_CALLBACK_<CLIENT>_TOKEN as its
    # bearer if set. A machine no plugin installed (one of yours) is not sent.
    set -euo pipefail
    var="PLUGIN_SHARE_CALLBACK_$(tr 'a-z-' 'A-Z_' <<<"$DECREE_DATA_CLIENT")"; tok="${var}_TOKEN"
    m="${DECREE_DATA_MACHINE:-}"
    file="${DECREE_RUN_DIR}/${m:-machines}.md"
    if [[ -n "$m" ]]; then
        if [[ -f ".decree/plugins/${m}.md" ]]; then cp ".decree/plugins/${m}.md" "$file"
        else echo "plugin_share: ${m} was installed by no plugin; nothing to send" >&2; exit 1; fi
    else
        allow=" $(tr ',' ' ' <<<"${PLUGIN_SHARE_ALLOW:-}") "
        { printf -- '---\ncatalog: true\n---\n'
          for f in .decree/machines/*/machine.yml; do
              n="$(basename "$(dirname "$f")")"; how=asks; [[ "$allow" != *" ${n} "* ]] || how=free
              printf -- '- %s (%s): %s\n' "$n" "$how" "$(yq -r '.description // ""' "$f")"
          done; } > "$file"
    fi
    auth=(); [[ -z "${!tok:-}" ]] || auth=(-H "Authorization: Bearer ${!tok}")
    curl -fsS --max-time 30 --retry 3 -X POST "${!var}" -H 'Content-Type: text/markdown' "${auth[@]}" \
        --data-binary @"$file" >/dev/null
    echo "plugin_share: sent ${m:-the list of machines} to ${DECREE_DATA_CLIENT}"
x-exist-endpoints:
  - path: /plugins/share/{client}
    patterns: {client: "[a-z0-9_-]{1,40}"}
    body: optional
    message:
      machine: plugin_share
      params: {client: "{{client}}"}
  - path: /plugins/{machine}/share/{client}
    patterns: {machine: "[a-z][a-z0-9_]{0,40}", client: "[a-z0-9_-]{1,40}"}
    body: optional
    message:
      machine: plugin_share
      params: {machine: "{{machine}}", client: "{{client}}"}
---
# plugin_share

Send one of this stack's machines, as a plugin file, to a client that asked for it, once it is shared freely or you say yes; or, asked for none, the list of them.

