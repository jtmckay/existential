#!/usr/bin/env bash
# flows.sh — read the flows and what the workspace has on. Sourced only, never
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
#   project     host: the host's own decree project (host/.decree), not the workspace's
#
# then its cron and migrations (lib/automations/plugin.sh installs those), and
# its body: what is left for a person. What the workspace has on is
# workspace/.decree/plugins.yml (`on:`), written from automation/plugins.exist.yml
# the first time; plugins are installed from it by src/lib/plugin.sh.

FLOWS_DIR="${REPO_DIR}/automation/plugins/flows"
FLOWS_DECREE="volumes/workspace_data/.decree"      # relative to REPO_DIR
PLUGINS_YML="${FLOWS_DECREE}/plugins.yml"
PLUGINS_SEED="automation/plugins.exist.yml"
PLUGINS_HOST_SEED="automation/plugins.host.exist.yml"

flow_fm()    { awk 'NR==1 && /^---$/{f=1;next} f && /^---$/{exit} f' "${FLOWS_DIR}/$1.md" 2>/dev/null; }
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

# What a project has on: its plugins.yml. None is nothing on: a worker never has
# the workspace's, and its example is what an install starts with, not what runs.
# A flow is the workspace's (automation) unless it says `project: host`: the
# host's own decree project, host/.decree, for what runs on the host itself.
_plugins_files() {  # <name>: "<plugins.yml> <its example>", relative to REPO_DIR
    if [[ "$(flow_get "$1" project)" == host ]]; then echo "host/.decree/plugins.yml ${PLUGINS_HOST_SEED}"
    else echo "${PLUGINS_YML} ${PLUGINS_SEED}"; fi
}
plugins_on() {  # [name]: what the project that name belongs to has on
    local yml seed f
    read -r yml seed <<<"$(_plugins_files "${1:-}")"
    f="${REPO_DIR}/${yml}"; [[ -f "$f" ]] || return 0
    _yaml_list on < "$f"
}
flow_on() { plugins_on "$1" | grep -qxF "$1"; }
# The flows every install starts with.
flow_defaults() { _yaml_list on < "${REPO_DIR}/${PLUGINS_SEED}"; }

# plugins_turn on|off <name>: add it to its project's plugins.yml, or take it out.
# Written from the example first if there is none. awk, not yq: e2e runs this on the host.
plugins_turn() {
    local yml seed f tmp
    read -r yml seed <<<"$(_plugins_files "$2")"
    f="${REPO_DIR}/${yml}"
    mkdir -p "$(dirname "$f")"
    [[ -f "$f" ]] || cp "${REPO_DIR}/${seed}" "$f"
    flow_on "$2" && [[ "$1" == on ]] && return 0
    tmp="${f}.tmp"
    awk -v op="$1" -v n="$2" '
        /^on:[[:space:]]*\[[[:space:]]*\][[:space:]]*$/ { print "on:"; if (op == "on") print "  - " n; next }
        /^on:[[:space:]]*$/ { print; f = 1; if (op == "on") print "  - " n; next }
        f && /^[[:space:]]+-[[:space:]]/ { v = $0; sub(/^[[:space:]]+-[[:space:]]*/, "", v); sub(/[[:space:]]+#.*$/, "", v)
            if (op == "off" && v == n) next; print; next }
        { f = 0; print }' "$f" > "$tmp" && mv "$tmp" "$f"
}
