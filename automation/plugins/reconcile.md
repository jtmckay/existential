---
machine: plugin
automation: reconcile
project: automation
needs:
  - develop
chart:
  description: An automation spec in notes/automations/ was accepted or edited; have develop build it as an offer. Nothing is installed or removed here.
  data:
    path: {type: string, default: ""}
    change: {type: string, default: ""}
  initial: reconcile
  states:
    reconcile:
      invoke: reconcile
      transitions: {done: done}
      emits: [develop, notify]
    done: {final: true}
    failed: {final: true}
scripts:
  reconcile: |
    #!/usr/bin/env bash
    # reconcile — notes/automations/<name>.md is what one automation should do.
    #
    # You say "build this" by moving a spec automation_propose wrote from
    # ai/proposed/ into notes/automations/, and may edit it there:
    #   accepted, edited  develop builds it as a plugin file and offers it in
    #                     ai/proposed/<name>.md. You read that and accept it on the
    #                     host; an edit means a new offer to accept
    #   deleted           you are told how to turn it off, on the host
    # Nothing is installed or removed here, and nothing here could: machines/,
    # scripts/ and lib/ are read-only in every container.
    set -euo pipefail

    WS="${AUTOMATIONS_WORKSPACE:-/workspace}"
    rel="${DECREE_DATA_PATH:?run by the notes/automations file handler, with a path}"
    change="${DECREE_DATA_CHANGE:-modified}"
    name="$(basename "$rel" .md)"
    say() {  # <title> <body>
        echo "reconcile: $2"
        printf '%s\n' "$2" | decree emit --machine notify --param ntfy_title="$1" --param ntfy_tags=robot >/dev/null
    }

    [[ "$name" =~ ^[a-z][a-z0-9_]{2,40}$ ]] || { say "Automation not built" "${rel}: '${name}' is not a machine name (lowercase, digits and _)."; exit 1; }

    if [[ "$change" == deleted ]]; then
        [[ ! -e ".decree/machines/${name}.yml" ]] ||
            say "Automation still on" "${rel} was deleted, and ${name} still runs. To turn it off, on the host: ./existential.sh run plugin off ${name}"
        exit 0
    fi

    spec="${WS}/${rel}"
    fm() { sed -n "2,/^---\$/s/^$1: *//p" "$spec" | head -1; }
    if [[ "$(fm machine)" == plugin ]]; then
        say "Not installed" "${rel} is a plugin file, and moving it here installs nothing. Put it back in ai/proposed/ and, on the host: ./existential.sh run plugin accept ${name}"
        exit 0
    fi
    [[ "$(fm machine)" == develop && "$(fm automation)" == "$name" ]] ||
        { say "Automation not built" "${rel} needs 'machine: develop' and 'automation: ${name}' in its frontmatter."; exit 1; }

    decree emit --machine develop --param automation="$name" --param from="$(fm from)" < "$spec" >/dev/null
    say "Building an automation" "${name}: develop builds it from ${rel} now, and tells you when it is ready to review. Nothing runs until you accept it on the host."
---
# reconcile

An automation spec in notes/automations/ was accepted or edited; have develop build it as an offer. Nothing is installed or removed here.
