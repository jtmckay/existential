#!/usr/bin/env bash
# plugins.sh — the repo's plugins, on and off, in each decree project.
#
#   ./existential.sh plugin [list]
#   ./existential.sh plugin on|off <name>...
#   ./existential.sh plugin sync [project] [name...]
#   ./existential.sh plugin export <name>
#
# automation/plugins/ is every plugin there is, and none of it is on. What is on
# is each project's own .decree/plugins/.on: automation (workspace/.decree),
# backup (services/automation-backup) or host (the repo's own .decree, run by a
# daemon on the host), as the plugin's x-exist-project says. on/off edit that
# list in each project the plugin is tagged for and sync it at once: what is on,
# and all it needs, written into .decree/plugins/ and installed by `decree
# install` (automation/lib/plugin.sh). What a plugin needs that is not a plugin
# (a service, a model, a step only you can do) is on its docs page.
#
# A machine of your own is not here: write it as a plugin file in
# workspace/.decree/plugins/<name>.md and `decree install <name>` there. The sync
# leaves a plugin file whose name is not the repo's alone.
#
# export writes an installed plugin back to its file (`decree export`), from the
# most privileged project that runs it (host, then backup, then automation):
# nothing changed in the workspace is ever exported into what backup or the host
# runs. existential.sh runs this inside adhoc, where yq and decree are; on a host
# with neither docker nor podman, on the host, with the host's own.
set -euo pipefail

REPO_DIR="${REPO_DIR:-/repo}"
PLUGINS="${REPO_DIR}/automation/plugins"
WORKSPACE_DECREE="volumes/workspace_data/.decree"   # relative to REPO_DIR
# shellcheck source=../automation/lib/plugin.sh
. "${REPO_DIR}/automation/lib/plugin.sh"

# A project's .decree, from the repo root.
project_dir() {
    case "$1" in
        automation) echo "${REPO_DIR}/${WORKSPACE_DECREE}" ;;
        backup)     echo "${REPO_DIR}/services/automation-backup" ;;
        host)       echo "${REPO_DIR}/.decree" ;;
        *) echo "plugin: no project '$1' (automation, backup or host)" >&2; exit 2 ;;
    esac
}

# Enter the project: its root is the directory whose .decree/ it is.
enter() {  # <project>
    case "$1" in
        automation) mkdir -p "$(project_dir automation)"; cd "$(dirname "$(project_dir automation)")" ;;
        # The host's project is the repo's own .decree: what runs on the host
        # itself, and the machines that develop this repo.
        host)       mkdir -p "${REPO_DIR}/.decree"; cd "${REPO_DIR}" ;;
        backup)     # services/automation-backup/ is itself the project, mounted as .decree.
                    local root; root="$(mktemp -d)"
                    ln -s "$(project_dir backup)" "${root}/.decree"
                    cd "$root" ;;
        *) project_dir "$1" ;;
    esac
}

# The projects a plugin's changes reach here: backup only while it is enabled
# (its exist.initial.sh has made the project's folders).
here() {  # <project>
    [[ "$1" != backup || -d "$(project_dir backup)/plugins" ]]
}
tags() { plugin_tags "${PLUGINS}/$1.md"; }   # <name>
# The most privileged project that runs it: where export reads it from.
source_of() {  # <name>
    local p
    for p in host backup automation; do tags "$1" | grep -qxF "$p" && { echo "$p"; return 0; }; done
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

# For file_advise: every machine this project could run, installed or not, and what it does.
catalog() {
    local f n
    for f in "$PLUGINS"/*.md; do
        n="$(basename "$f" .md)"
        plugin_tags "$f" | grep -qxF automation || continue
        d="$(yq --front-matter=extract -r '.machine.description // ""' "$f")"
        [[ -n "$d" ]] || continue
        printf '%s\t%s\t%s\n' "$n" "$([[ -f ".decree/plugins/${n}.md" ]] && echo on || echo off)" "$d"
    done > .decree/plugins.tsv
}

sync_project() {  # <project> [name...]
    local p="$1" rc=0; shift
    enter "$p"
    kernel "$p"
    plugin_sync "$PLUGINS" "$p" "$@" || rc=$?
    [[ "$p" != automation ]] || catalog
    return $rc
}

cmd="${1:-list}"; shift || true
case "$cmd" in
    list)
        for f in "$PLUGINS"/*.md; do
            n="$(basename "$f" .md)"; mark="  "; where=""
            for p in $(tags "$n"); do
                d="$(project_dir "$p")"; where+="${where:+,}${p}"
                if grep -qxF "$n" "${d}/plugins/.on" 2>/dev/null; then mark="on"
                elif [[ "$mark" != on && -f "${d}/plugins/${n}.md" ]]; then mark=" +"; fi
            done
            printf '  %-3s %-26s %-18s %s\n' "$mark" "$n" "$where" \
                "$(yq --front-matter=extract -r '.machine.description // (.extends | select(.) | "decree'"'"'s " + . + ", extended") // "lib, for the plugins that need it"' "$f" | cut -c1-80)"
        done
        echo ""
        echo "on: you turned it on.  +: on because something on needs it."
        echo "Turn one on:  ./existential.sh plugin on <name>   (what it needs comes with it)"
        echo "What each does, and what it wants beyond a plugin: https://existential.company/docs/flows"
        exit 3 ;;
    on|off)
        [[ $# -gt 0 ]] || { echo "usage: plugin ${cmd} <name>..." >&2; exit 2; }
        touched=" "
        for n in "$@"; do
            [[ -f "${PLUGINS}/${n}.md" ]] || { echo "plugin: no ${n} in automation/plugins/ (./existential.sh plugin list)" >&2; exit 1; }
            for p in $(tags "$n"); do
                if ! here "$p"; then echo "plugin: ${n} runs in automation-backup, which is off: ./existential.sh service on automation-backup"; continue; fi
                ( enter "$p"; plugin_turn "$cmd" "$PLUGINS" "$p" "$n" )
                touched+="${p} "
            done
        done
        rc=0
        for p in $touched; do ( sync_project "$p" ) || rc=1; done
        for n in "$@"; do
            for p in $(tags "$n"); do
                here "$p" || continue
                d="$(project_dir "$p")"
                if [[ "$cmd" == on ]]; then echo "  ✓ ${n} is on (${p})"
                elif [[ -f "${d}/plugins/${n}.md" ]]; then echo "  ${n} is still installed (${p}): something on needs it"
                else echo "  ${n} is off (${p})"; fi
            done
        done
        [[ "$cmd" == off || "$touched" == " " ]] || echo "  docker compose up -d starts what is new; what it needs beyond a plugin: https://existential.company/docs/flows"
        exit $rc ;;
    sync)
        sync_project "${1:-automation}" "${@:2}" ;;
    export)
        [[ -n "${1:-}" ]] || { echo "usage: plugin export <name>" >&2; exit 2; }
        n="$1"; p="$(source_of "$n")"; dst="${PLUGINS}/${n}.md"
        enter "$p"
        decree export --no-color "$n" >/dev/null
        out="$(mktemp)"; cp ".decree/plugins/${n}.md" "$out"
        # None of the machines a note starts, which the sync adds to note_watch.
        if [[ "$n" == note_watch ]]; then
            yq --front-matter=extract '.machine.states.watch.emits' "$dst" > "${out}.e"
            e="${out}.e" yq --front-matter=process -i '.machine.states.watch.emits = load(strenv(e))' "$out"; rm -f "${out}.e"
        fi
        mv "$out" "$dst"; chmod 644 "$dst"
        echo "Wrote ${dst#"${REPO_DIR}/"} from the ${p} project — commit it, and every install that has it on gets it on its next pull." ;;
    *) echo "usage: plugin [list | on <name>... | off <name>... | sync [project] [name...] | export <name>]" >&2; exit 2 ;;
esac
