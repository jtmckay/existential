#!/usr/bin/env bash
# flows.sh — read flows/<name>/flow.md. Sourced only, never run; needs REPO_DIR.
#
# A flow is one thing the stack does for you, curated: the decree machine(s) it
# runs, the services that must be on first, and the files that switch it on.
# Its folder name is its id. flow.md is frontmatter plus what is left for a
# person to do; the frontmatter is flat on purpose (scalars and block lists of
# plain values), so this reads it with awk on a host that has no yq:
#
#   name        a title
#   tagline     one line
#   docs        the site page that explains it (/docs/...)
#   services    EXIST_IS_* flags it turns on
#   flows       other flows it needs, turned on first
#   processors  file processors it copies from automation/lib/file-processors.example/
#   default     true: on in every install until turned off
#   e2e         true: ./existential.sh e2e brings a fresh install up with it
#
# Its files: cron/*.md and migrations/*.md, copied into the workspace's decree
# project; examples/ is for reading and is never copied.

FLOWS_DIR="${REPO_DIR}/flows"
FLOWS_DECREE="volumes/workspace_data/.decree"      # relative to REPO_DIR
# A default flow named here stays off: exist.initial.sh would otherwise put it back.
FLOWS_OFF="${FLOWS_DECREE}/flows-off"

flow_fm()    { awk 'NR==1 && /^---$/{f=1;next} f && /^---$/{exit} f' "${FLOWS_DIR}/$1/flow.md" 2>/dev/null; }
flow_body()  { awk 'NR==1 && /^---$/{f=1;next} f && /^---$/{f=0;b=1;next} b' "${FLOWS_DIR}/$1/flow.md"; }
flow_get()   { flow_fm "$1" | sed -n "s/^$2:[[:space:]]*//p" | head -1 | sed 's/^"\(.*\)"$/\1/'; }
flow_list()  {
    flow_fm "$1" | awk -v k="$2" '
        $0 ~ "^" k ":[[:space:]]*$" { f = 1; next }
        f && /^[[:space:]]+-[[:space:]]/ { sub(/^[[:space:]]+-[[:space:]]*/, ""); sub(/[[:space:]]+#.*$/, ""); print; next }
        f { exit }'
}
flow_names() { local d; for d in "${FLOWS_DIR}"/*/flow.md; do [[ -f "$d" ]] && basename "$(dirname "$d")"; done; return 0; }
flow_exists() { [[ -f "${FLOWS_DIR}/$1/flow.md" ]]; }

# flow_closure <name>: the flows it needs, depth first, then itself; each once.
flow_closure() {
    local _seen=" "   # a word list, not local -A: this runs on a Mac's bash 3.2
    _flow_visit() {
        local f
        [[ "$_seen" == *" $1 "* ]] && return 0
        _seen+="$1 "
        for f in $(flow_list "$1" flows); do _flow_visit "$f"; done
        echo "$1"
    }
    _flow_visit "$1"
}

# flow_files <name>: what switches it on, as "src<TAB>dst" relative to REPO_DIR.
flow_files() {
    local f p
    for f in "${FLOWS_DIR}/$1"/cron/*.md "${FLOWS_DIR}/$1"/migrations/*.md; do
        [[ -f "$f" ]] || continue
        p="${f#"${FLOWS_DIR}/$1/"}"
        printf 'flows/%s/%s\t%s/%s\n' "$1" "$p" "$FLOWS_DECREE" "$p"
    done
    for p in $(flow_list "$1" processors); do
        printf 'automation/lib/file-processors.example/%s\tautomation/lib/file-processors/%s\n' "$p" "$p"
    done
}

# flow_file_on <dst>: the file is in place, or, for a migration, has already run.
# decree_seed: the repo's machines, scripts and graphs are the workspace project's
# starting set; each file it lacks is copied once and never again, so an edit wins.
# flow_activate runs it first: a daemon that sees a migration before its machine
# fails it with "unknown machine".
decree_seed() {
    local d f
    for d in machines scripts graph; do
        while IFS= read -r f; do
            [[ -e "${REPO_DIR}/${FLOWS_DECREE}/${d}/${f}" ]] && continue
            mkdir -p "$(dirname "${REPO_DIR}/${FLOWS_DECREE}/${d}/${f}")"
            cp -p "${REPO_DIR}/automation/${d}/${f}" "${REPO_DIR}/${FLOWS_DECREE}/${d}/${f}"
        done < <(cd "${REPO_DIR}/automation/${d}" && find . -type f ! -name '.gitkeep' | sed 's|^\./||')
    done
}

flow_file_on() {
    [[ -e "${REPO_DIR}/$1" ]] && return 0
    [[ "$1" == */migrations/* ]] && grep -qxF "${1##*/}" "${REPO_DIR}/${FLOWS_DECREE}/processed.md" 2>/dev/null
}

# flow_on <name> [env file]: every service it names is true, and every file is in place.
flow_on() {
    local env="${2:-${REPO_DIR}/.env.shared}" v src dst
    for v in $(flow_list "$1" services); do grep -qE "^${v}=true" "$env" 2>/dev/null || return 1; done
    while IFS=$'\t' read -r src dst; do flow_file_on "$dst" || return 1; done < <(flow_files "$1")
    return 0
}

# flow_activate <name>: copy in each file it lacks; prints each one copied.
flow_activate() {
    local src dst
    decree_seed
    while IFS=$'\t' read -r src dst; do
        flow_file_on "$dst" && continue
        mkdir -p "$(dirname "${REPO_DIR}/${dst}")"
        cp "${REPO_DIR}/${src}" "${REPO_DIR}/${dst}"
        echo "$dst"
    done < <(flow_files "$1")
}

# The default flows that are not turned off: exist.initial.sh activates these.
flow_defaults() {
    local n
    for n in $(flow_names); do
        [[ "$(flow_get "$n" default)" == true ]] || continue
        grep -qxF "$n" "${REPO_DIR}/${FLOWS_OFF}" 2>/dev/null && continue
        echo "$n"
    done
    return 0
}
