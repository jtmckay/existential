#!/usr/bin/env bash
# plugin.sh — which of the repo's plugins (automation/plugins/) are on, and the
# sync that keeps each decree project's installed and current.
#
#   ./existential.sh run plugin [list]
#   ./existential.sh run plugin on|off <name>
#   ./existential.sh run plugin sync [project] [name...]
#   ./existential.sh run plugin export <name>
#
# A machine of your own is not here: write it as a plugin file in
# workspace/.decree/plugins/<name>.md and `decree install <name>` there. The sync
# leaves a plugin file it did not write alone.
#
# automation/plugins.yml is the one record of what is on, written from
# automation/plugins.exist.yml the first time. A plugin's x-exist-project says
# which decree project runs it: automation (workspace/.decree), backup
# (services/automation-backup) or host (the repo's own .decree, run by a daemon
# on the host). on/off edit the list; sync writes, into one project's
# .decree/plugins/, what is on and tagged for it and what that needs, and `decree
# install` installs it (lib/plugin.sh). A flow is a plugin in
# automation/plugins/flows/; ./existential.sh flow is the same list, for flows.
# export writes an installed plugin back to its file (`decree export`), from the
# most privileged project that runs it (host, then backup, then automation):
# nothing changed in the workspace is ever exported into what backup or the host
# runs. existential.sh runs it inside adhoc, where yq and decree are; on a host
# with neither docker nor podman, on the host, with the host's own.
set -euo pipefail

REPO_DIR="${REPO_DIR:-/repo}"
PLUGINS="${REPO_DIR}/automation/plugins"
# shellcheck source=../../automation/lib/plugin.sh
. "${REPO_DIR}/automation/lib/plugin.sh"
# shellcheck source=../utils/flows.sh
. "${REPO_DIR}/src/utils/flows.sh"

# Enter the project: its root is the directory whose .decree/ it is.
enter() {  # <project> [ro: only look, so a missing project is an empty one]
    case "$1" in
        automation) if [[ -d "${REPO_DIR}/${FLOWS_DECREE}" || -z "${2:-}" ]]; then
                        mkdir -p "${REPO_DIR}/${FLOWS_DECREE}"; cd "${REPO_DIR}/${FLOWS_DECREE%/.decree}"
                    else cd "$(mktemp -d)"; fi ;;
        # The host's project is the repo's own .decree: what runs on the host
        # itself, and the machines that develop this repo.
        host)       mkdir -p "${REPO_DIR}/.decree"; cd "${REPO_DIR}" ;;
        backup)     # services/automation-backup/ is itself the project, mounted as .decree.
                    local root; root="$(mktemp -d)"
                    ln -s "${REPO_DIR}/services/automation-backup" "${root}/.decree"
                    cd "$root" ;;
        *) echo "plugin: no project '$1' (automation, backup or host)" >&2; exit 2 ;;
    esac
}

# automation/plugins.yml, once (plugins_seed). An install from before any
# plugins.yml keeps what it had: a flow whose cron or migration is already in the
# workspace is on, and a default flow it had turned off (flows-off) stays off.
seed() {
    local cfg="${REPO_DIR}/${PLUGINS_YML}" d="${REPO_DIR}/${FLOWS_DECREE}" f n k
    [[ -f "$cfg" ]] && return 0
    local listed=false; [[ -f "${d}/plugins.yml" ]] && listed=true
    plugins_seed
    $listed || [[ ! -d "$d" ]] && return 0
    for f in "$PLUGINS"/flows/*.md; do
        n="$(basename "$f" .md)"
        for k in $(yq --front-matter=extract -r '((.cron // {}) | keys | .[] | "cron/" + .), ((.order // {}) | keys | .[] | "migrations/" + .)' "$f"); do
            if [[ -e "${d}/${k}" ]] || grep -qxF "${k#migrations/}" "${d}/processed.md" 2>/dev/null; then
                n="$n" yq -i '.on = ((.on // []) + [strenv(n)] | unique)' "$cfg"; break
            fi
        done
    done
    if [[ -f "${d}/flows-off" ]]; then
        while IFS= read -r n; do [[ -n "$n" ]] && n="$n" yq -i '.on -= [strenv(n)]' "$cfg"; done < "${d}/flows-off"
        rm -f "${d}/flows-off"
    fi
}

# The projects a plugin's changes reach here: backup only while it is enabled
# (its exist.initial.sh has made the project's folders).
here() {  # <project>
    [[ "$1" != backup || -d "${REPO_DIR}/services/automation-backup/plugins" ]]
}
# The most privileged project that runs it: where export reads it from.
source_of() {  # <name>
    local p
    for p in host backup automation; do plugin_in "$p" "$1" && { echo "$p"; return 0; }; done
    echo automation
}

# automation/lib/ is what more than one plugin uses, so every project gets all
# of it, kept equal to the checkout: a file gone from the repo goes from lib/
# too. A plugin's own lib files are not in it, so this never touches them.
shared_lib() {
    local list=".decree/lib/.shared" f
    mkdir -p .decree/lib
    if [[ -f "$list" ]]; then
        while IFS= read -r f; do
            [[ -n "$f" && ! -e "${REPO_DIR}/automation/lib/${f}" ]] && rm -f ".decree/lib/${f}"
        done < "$list"
    fi
    cp -rp "${REPO_DIR}"/automation/lib/. .decree/lib/
    (cd "${REPO_DIR}/automation/lib" && find . -type f | sed 's|^\./||' | sort) > "$list"
}

# The plugin system's own lib, and its endpoints the workspace lacks. Its
# machines are plugins (PLUGIN_KERNEL), installed by the sync. host gets no
# shared lib: ntfy is on the docker network, so a host plugin tells you through
# the automation container.
kernel() {  # <project>
    local path
    [[ "$1" != host ]] || return 0
    shared_lib
    [[ "$1" == automation && -f "$REST" ]] || return 0
    for path in $(yq -r '.endpoints[] | select(.message.machine | test("^notify$")) | .path' "${REPO_DIR}/automation/decree-go-rest.exist.yml"); do
        p="$path" yq -e '.endpoints[] | select(.path == strenv(p))' "$REST" >/dev/null 2>&1 && continue
        p="$path" r="${REPO_DIR}/automation/decree-go-rest.exist.yml" yq -i '.endpoints += [load(strenv(r)).endpoints[] | select(.path == strenv(p))]' "$REST"
    done
}

sync_project() {  # <project> [name...]
    local p="$1"; shift
    enter "$p"
    kernel "$p"
    plugin_sync "$PLUGINS" "$p" "$@"
}

cmd="${1:-list}"; shift || true
case "$cmd" in
    list)
        seed
        on=" $(plugins_on | tr '\n' ' ') "
        for f in "$PLUGINS"/*.md "$PLUGINS"/flows/*.md; do
            [[ -f "$f" ]] || continue
            n="$(basename "$f" .md)"
            mark="  "; [[ "$on" == *" ${n} "* ]] && mark="on"
            printf '  %-3s %-28s %-18s %s\n' "$mark" "$n" "$(plugin_projects "$n" | paste -sd, -)" \
                "$(yq --front-matter=extract -r '.["x-exist-tagline"] // .machine.description // (.extends | select(.) | "decree'"'"'s " + . + ", extended") // ""' "$f" | cut -c1-80)"
        done
        echo ""; echo "Turn one on:  ./existential.sh run plugin on <name>   (what it needs comes with it)" ;;
    on|off)
        [[ -n "${1:-}" ]] || { echo "usage: plugin ${cmd} <name>" >&2; exit 2; }
        n="${1##*/}"    # host/<name> and backup/<name>, as it was written before the tag
        plugin_src "$PLUGINS" "$n" >/dev/null || { echo "plugin: no ${n} in automation/plugins/" >&2; exit 1; }
        seed; plugins_turn "$cmd" "$n"
        for p in $(plugin_projects "$n"); do if here "$p"; then ( sync_project "$p" ); fi; done ;;
    sync)
        seed; sync_project "${1:-automation}" "${@:2}" ;;
    export)
        [[ -n "${1:-}" ]] || { echo "usage: plugin export <name>" >&2; exit 2; }
        n="${1##*/}"; p="$(source_of "$n")"
        dst="$(plugin_src "$PLUGINS" "$n" || echo "${PLUGINS}/${n}.md")"
        [[ "$dst" != */flows/* ]] || { echo "plugin: ${n} is a flow, which has no machine to export: edit ${dst#"${REPO_DIR}/"}" >&2; exit 1; }
        enter "$p"
        decree export --no-color "$n" >/dev/null
        out="$(mktemp)"; cp ".decree/plugins/${n}.md" "$out"
        # Its needs by the repo's names (a flow's is flow_<name> to decree), and none
        # of the machines a note starts, which the sync adds to note_watch.
        for f in "$PLUGINS"/flows/*.md; do
            a="flow_$(basename "$f" .md | tr - _)" b="$(basename "$f" .md)" yq --front-matter=process -i '(.needs[]? | select(. == strenv(a))) = strenv(b)' "$out"
        done
        if [[ "$n" == note_watch ]]; then
            yq --front-matter=extract '.machine.states.watch.emits' "$dst" > "${out}.e"
            e="${out}.e" yq --front-matter=process -i '.machine.states.watch.emits = load(strenv(e))' "$out"; rm -f "${out}.e"
        fi
        mv "$out" "$dst"; chmod 644 "$dst"
        echo "Wrote ${dst#"${REPO_DIR}/"} from the ${p} project — commit it, and every install that has it on gets it on its next pull." ;;
    seed)
        seed ;;
    *) echo "usage: plugin [list|on|off|sync|export|seed] ..." >&2; exit 2 ;;
esac
