#!/usr/bin/env bash
# automations/registry.sh — what is installed for each plugin, and how to take
# it out again. Sourced with plugin.sh, by the host's sync (which installs and
# removes) and by develop (which installs only into a scratch project, to check
# what it offers). Run from the decree project root.
#
# .decree/automations.yml lists every plugin installed:
#   - machine: business_idea_workup
#     kind: plugin
#     spec: automation/plugins/<name>.md, or automation/plugins/local/<name>.md
#           for one you accepted
#     when: <the kind of note that starts it>   so note_watch can match notes
#     endpoints: [<path>, ...]    in .decree/decree-go-rest.yml
#     crons: [<name>, ...]        in .decree/cron/
#     libs: [<path>, ...]         in .decree/lib/
#     migrations: [<file>, ...]   in .decree/migrations/
# An entry of kind note, file or cron is an automation an older install's develop
# built in place: it keeps running and is never rebuilt.
# Only a machine listed here is ever replaced or removed.
REGISTRY="${AUTOMATIONS_REGISTRY:-.decree/automations.yml}"
WATCH=".decree/machines/note_watch.yml"
HANDLERS=".decree/handlers.yml"
REST=".decree/decree-go-rest.yml"

automation_installed() {  # <name>: listed in the registry
    [[ -f "$REGISTRY" ]] && yq -e ".[] | select(.machine == \"$1\")" "$REGISTRY" >/dev/null 2>&1
}

automation_get() {  # <name> <field>
    yq -r ".[] | select(.machine == \"$1\") | .$2 // \"\"" "$REGISTRY"
}

# Remove machine, script(s), trigger and endpoints, and the registry entry. Only
# for a name the registry lists.
automation_remove() {  # <name>
    local name="$1" p
    automation_installed "$name" || return 0
    rm -f ".decree/machines/${name}.yml" ".decree/scripts/${name}.sh" ".decree/cron/${name}.md"
    rm -rf ".decree/scripts/${name}"
    while IFS= read -r p; do
        [[ -n "$p" ]] && rm -f ".decree/cron/${p}.md"
    done < <(yq -r ".[] | select(.machine == \"${name}\") | .crons[]?" "$REGISTRY")
    # Its lib files, and each folder they leave empty.
    while IFS= read -r p; do
        [[ -n "$p" ]] || continue
        rm -f ".decree/lib/${p}"
        p="$(dirname "$p")"
        while [[ "$p" != . ]] && rmdir ".decree/lib/${p}" 2>/dev/null; do p="$(dirname "$p")"; done
    done < <(yq -r ".[] | select(.machine == \"${name}\") | .libs[]?" "$REGISTRY")
    [[ -f "$HANDLERS" ]] && yq -i "del(.[] | select(.machine == \"${name}\"))" "$HANDLERS"
    [[ -f "$WATCH" ]] && yq -i ".states.watch.emits -= [\"${name}\"]" "$WATCH"
    while IFS= read -r p; do
        [[ -n "$p" && -f "$REST" ]] && p="$p" yq -i 'del(.endpoints[] | select(.path == strenv(p)))' "$REST"
    done < <(yq -r ".[] | select(.machine == \"${name}\") | .endpoints[]?" "$REGISTRY")
    yq -i "del(.[] | select(.machine == \"${name}\"))" "$REGISTRY"
}
