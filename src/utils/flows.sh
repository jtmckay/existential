#!/usr/bin/env bash
# flows.sh — read the flows, every plugin's project, and what is on. Sourced only, never
# run; needs REPO_DIR.
#
# A flow is a plugin with no machine, automation/plugins/flows/<name>.md: one
# curated thing the stack does. The ones with a tagline are what the person picks
# (./existential.sh flow); the rest are libraries other plugins need. Its
# frontmatter starts flat (scalars and block lists of plain values), so this
# reads it with awk on a host that has no yq:
#
#   name        a title
#   tagline     one line; a flow without one is a library, not offered
#   docs        the site page that explains it (/docs/...)
#   services    EXIST_IS_* flags turning it on turns on
#   needs       the plugins and flows it turns on with it
#   e2e         true: ./existential.sh e2e brings a fresh install up with it
#   project     which decree project runs it: automation, backup or host (a list
#               when more than one does). Every plugin has it, not only a flow
#
# then its cron and migrations (lib/automations/plugin.sh installs those), and
# its body: what is left for a person. What is on, for every project, is one file:
# automation/plugins.yml (`on:`, never committed), written from
# automation/plugins.exist.yml the first time. Each project installs the entries
# tagged for it (src/lib/plugin.sh).

FLOWS_DIR="${REPO_DIR}/automation/plugins/flows"
FLOWS_DECREE="volumes/workspace_data/.decree"      # relative to REPO_DIR
PLUGINS_YML="automation/plugins.yml"
PLUGINS_SEED="automation/plugins.exist.yml"

# Any plugin's file and frontmatter, a machine's or a flow's.
plugin_file() {
    if [[ -f "${FLOWS_DIR%/flows}/$1.md" ]]; then echo "${FLOWS_DIR%/flows}/$1.md"
    elif [[ -f "${FLOWS_DIR}/$1.md" ]]; then echo "${FLOWS_DIR}/$1.md"
    elif [[ -f "${FLOWS_DIR%/flows}/local/$1.md" ]]; then echo "${FLOWS_DIR%/flows}/local/$1.md"; else return 1; fi
}
_fm()        { awk 'NR==1 && /^---$/{f=1;next} f && /^---$/{exit} f' "$1" 2>/dev/null; }
# plugin_projects <name>: the projects that run it, one per line (none: automation).
plugin_projects() {
    local f s
    f="$(plugin_file "$1")" || return 0
    s="$(_fm "$f" | sed -n 's/^project:[[:space:]]*\([a-z]\)/\1/p' | head -1)"
    [[ -n "$s" ]] || s="$(_fm "$f" | _yaml_list project)"
    echo "${s:-automation}"
}
plugin_in() { plugin_projects "$2" | grep -qxF "$1"; }   # <project> <name>

flow_fm()    { _fm "${FLOWS_DIR}/$1.md"; }
flow_body()  { awk 'NR==1 && /^---$/{f=1;next} f && /^---$/{f=0;b=1;next} b' "${FLOWS_DIR}/$1.md"; }
flow_get()   { flow_fm "$1" | sed -n "s/^$2:[[:space:]]*//p" | head -1 | sed 's/^"\(.*\)"$/\1/'; }
# A list, block (`  - x`) or flow (`[x, y]`) style, of a top-level key.
_yaml_list() {  # <key>: reads stdin
    awk -v k="$1" '
        $0 ~ "^" k ":[[:space:]]*\\[" { s = $0; sub(/^[^[]*\[/, "", s); sub(/\].*$/, "", s)
            n = split(s, a, ","); for (i = 1; i <= n; i++) { gsub(/^[[:space:]]+|[[:space:]]+$/, "", a[i]); if (a[i] != "") print a[i] }; exit }
        $0 ~ "^" k ":[[:space:]]*$" { f = 1; next }
        f && /^[[:space:]]+-[[:space:]]/ { sub(/^[[:space:]]+-[[:space:]]*/, ""); sub(/[[:space:]]+#.*$/, ""); print; next }
        f { exit }'
}
flow_list()  { flow_fm "$1" | _yaml_list "$2"; }
flow_exists() { [[ -f "${FLOWS_DIR}/$1.md" && -n "$(flow_get "$1" tagline)" ]]; }
flow_names() {
    local f n
    for f in "${FLOWS_DIR}"/*.md; do
        [[ -f "$f" ]] || continue
        n="$(basename "$f" .md)"; flow_exists "$n" && echo "$n"
    done
    return 0
}

# flow_closure <name>: the flows it needs, depth first, then itself; each once.
flow_closure() {
    local _seen=" "   # a word list, not local -A: this runs on a Mac's bash 3.2
    _flow_visit() {
        local f
        [[ "$_seen" == *" $1 "* ]] && return 0
        _seen+="$1 "
        for f in $(flow_list "$1" needs); do flow_exists "$f" && _flow_visit "$f"; done
        echo "$1"
    }
    _flow_visit "$1"
}

# What is on: automation/plugins.yml. None is nothing on: its example is what an
# install starts with, not what runs.
plugins_on() {
    local f="${REPO_DIR}/${PLUGINS_YML}"
    [[ -f "$f" ]] || return 0
    _yaml_list on < "$f"
}
flow_on() { plugins_on | grep -qxF "$1"; }
# The flows every install starts with.
flow_defaults() { _yaml_list on < "${REPO_DIR}/${PLUGINS_SEED}"; }

# plugins_seed: automation/plugins.yml from its example, once. An install from
# when each project had its own list (workspace/.decree, host/.decree,
# services/automation-backup) keeps what each had on: a project with a list gets
# that list in place of the example's entries for it, and the old file goes.
# awk, not yq: a worker with no engine runs this on the host.
plugins_seed() {
    local f="${REPO_DIR}/${PLUGINS_YML}" p old n
    [[ -f "$f" ]] && return 0
    mkdir -p "$(dirname "$f")"
    cp "${REPO_DIR}/${PLUGINS_SEED}" "$f"
    for p in automation:"${FLOWS_DECREE}" backup:services/automation-backup host:host/.decree; do
        old="${REPO_DIR}/${p#*:}/plugins.yml"; p="${p%%:*}"
        [[ -f "$old" ]] || continue
        for n in $(flow_defaults); do
            [[ "$(plugin_projects "$n" | xargs)" == "$p" ]] && _plugins_edit off "$n"
        done
        for n in $(_yaml_list on < "$old"); do _plugins_edit on "$n"; done
        grep -q '^auto_update:[[:space:]]*false' "$old" && { sed 's/^auto_update:.*/auto_update: false/' "$f" > "${f}.tmp" && mv "${f}.tmp" "$f"; }
        rm -f "$old"
        echo "  ${old#"${REPO_DIR}/"} is now part of ${PLUGINS_YML}, the one list of what is on."
    done
}

# plugins_turn on|off <name>: add it to automation/plugins.yml, or take it out.
plugins_turn() { plugins_seed; _plugins_edit "$@"; }
_plugins_edit() {
    local f="${REPO_DIR}/${PLUGINS_YML}" tmp
    if [[ "$1" == on ]] && _yaml_list on < "$f" | grep -qxF "$2"; then return 0; fi
    tmp="${f}.tmp"
    awk -v op="$1" -v n="$2" '
        /^on:[[:space:]]*\[[[:space:]]*\][[:space:]]*$/ { print "on:"; if (op == "on") print "  - " n; next }
        /^on:[[:space:]]*$/ { print; f = 1; if (op == "on") print "  - " n; next }
        f && /^[[:space:]]+-[[:space:]]/ { v = $0; sub(/^[[:space:]]+-[[:space:]]*/, "", v); sub(/[[:space:]]+#.*$/, "", v)
            if (op == "off" && v == n) next; print; next }
        { f = 0; print }' "$f" > "$tmp" && mv "$tmp" "$f"
}
