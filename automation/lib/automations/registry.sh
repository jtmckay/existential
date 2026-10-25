#!/usr/bin/env bash
# automations/registry.sh — what is installed for each automation, and how to
# take it out again. Sourced by develop (which installs) and reconcile (which
# removes one whose spec was deleted). Run from the decree project root.
#
# .decree/automations.yml lists every automation develop built:
#   - machine: business_idea_workup
#     kind: note | file | cron
#     when: <the note event, for kind note>   match/changes/quiet: <kind file>   cron: <kind cron>
#     note: notes/process.md      the note that asked for it (it never triggers on it)
#     spec: notes/automations/business_idea_workup.md
#     migration: A202610250830-business_idea_workup.md
# Only a machine listed here is ever replaced or removed, so no spec can touch a
# machine decree ships or you wrote.
REGISTRY="${AUTOMATIONS_REGISTRY:-.decree/automations.yml}"
WATCH=".decree/machines/note_watch.yml"
HANDLERS=".decree/handlers.yml"

automation_installed() {  # <name>: listed in the registry
    [[ -f "$REGISTRY" ]] && yq -e ".[] | select(.machine == \"$1\")" "$REGISTRY" >/dev/null 2>&1
}

automation_get() {  # <name> <field>
    yq -r ".[] | select(.machine == \"$1\") | .$2 // \"\"" "$REGISTRY"
}

# Remove machine, script and trigger, and the registry entry. Only for a name the
# registry lists.
automation_remove() {  # <name>
    local name="$1"
    automation_installed "$name" || return 0
    rm -f ".decree/machines/${name}.yml" ".decree/scripts/${name}.sh" ".decree/cron/${name}.md"
    [[ -f "$HANDLERS" ]] && yq -i "del(.[] | select(.machine == \"${name}\"))" "$HANDLERS"
    [[ -f "$WATCH" ]] && yq -i ".states.watch.emits -= [\"${name}\"]" "$WATCH"
    yq -i "del(.[] | select(.machine == \"${name}\"))" "$REGISTRY"
}
