#!/usr/bin/env bash
# plugin.sh — which of the repo's plugins (automation/plugins/) are on, and the
# sync that keeps each decree project's installed and current.
#
#   ./existential.sh run plugin [list]
#   ./existential.sh run plugin on|off <name>
#   ./existential.sh run plugin sync [project] [name...]
#   ./existential.sh run plugin export <name>
#   ./existential.sh run plugin offers            what waits in workspace/ai/proposed/
#   ./existential.sh run plugin accept <name>     read one, say yes, and it is installed
#
# accept is the only way anything made in the workspace becomes a machine: every
# container that mounts the workspace has machines/, scripts/ and lib/ read-only,
# so develop, an agent in code-server or another stack can only offer a plugin
# file (workspace/ai/proposed/<name>.md). A person reads it and accepts it here,
# on the host, at a terminal. It is kept in automation/plugins/local/ (never in
# git), for the automation project alone.
#
# automation/plugins.yml is the one record of what is on, written from
# automation/plugins.exist.yml the first time. A plugin's `project:` says which
# decree project runs it: automation (workspace/.decree), backup
# (services/automation-backup) or host (the repo's own .decree, run by a daemon
# on the host). on/off edit the list; sync installs, into one project, what is on
# and tagged for it and what that needs, the new version of what changed, and
# removes what is no longer wanted (lib/automations/plugin.sh). A flow is a
# plugin in automation/plugins/flows/; ./existential.sh flow is the same list,
# for flows. export writes an installed plugin back to its file, from the most
# privileged project that runs it (host, then backup, then automation): nothing
# changed in the workspace is ever exported into what backup or the host runs.
# existential.sh runs it inside adhoc, where yq and decree are; on a host with
# neither docker nor podman, on the host, with the host's own.
set -euo pipefail

REPO_DIR="${REPO_DIR:-/repo}"
PLUGINS="${REPO_DIR}/automation/plugins"
# shellcheck source=../../automation/lib/automations/registry.sh
. "${REPO_DIR}/automation/lib/automations/registry.sh"
# shellcheck source=../../automation/lib/automations/plugin.sh
. "${REPO_DIR}/automation/lib/automations/plugin.sh"
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
    export DECREE_RUN_DIR; DECREE_RUN_DIR="$(mktemp -d)"
}

# automation/plugins.yml, once (plugins_seed). An install from before any
# plugins.yml keeps what it had: a flow whose cron or migration is already in the
# workspace is on, and a default flow it had turned off (flows-off) stays off.
seed() {  # <project>
    local cfg="${REPO_DIR}/${PLUGINS_YML}" d="${REPO_DIR}/${FLOWS_DECREE}" f n k
    [[ -f "$cfg" ]] && return 0
    local listed=false; [[ -f "${d}/plugins.yml" ]] && listed=true
    plugins_seed
    $listed || [[ ! -d "$d" ]] && return 0
    for f in "$PLUGINS"/flows/*.md; do
        n="$(basename "$f" .md)"
        for k in $(yq --front-matter=extract -r '((.cron // {}) | keys | .[] | "cron/" + . + ".md"), ((.migrations // {}) | keys | .[] | "migrations/" + . + ".md")' "$f"); do
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
    [[ "$1" != backup || -d "${REPO_DIR}/services/automation-backup/machines" ]]
}
# The most privileged project that runs it: where export reads it from.
source_of() {  # <name>
    local p
    for p in host backup automation; do plugin_in "$p" "$1" && { echo "$p"; return 0; }; done
    echo automation
}

# automation/lib/ is what more than one plugin uses, so every project gets all
# of it, kept equal to the checkout: a file gone from the repo (a file processor
# whose flow went off) goes from lib/ too. A plugin's own lib files are not in
# it, so this never touches them.
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
    mkdir -p .decree/machines .decree/scripts
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
        for f in "$PLUGINS"/*.md "$PLUGINS"/flows/*.md "$PLUGINS"/local/*.md; do
            [[ -f "$f" ]] || continue
            n="$(basename "$f" .md)"
            mark="  "; [[ "$on" == *" ${n} "* ]] && mark="on"
            printf '  %-3s %-28s %-18s %s\n' "$mark" "$n" "$(plugin_projects "$n" | paste -sd, -)" "$(yq --front-matter=extract -r '.tagline // .chart.description // ""' "$f" | cut -c1-80)"
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
        enter "$p"
        dst="$(plugin_src "$PLUGINS" "$n" || echo "${PLUGINS}/${n}.md")"
        out="$(mktemp)"; plugin_export "$n" > "$out"
        mv "$out" "$dst"; chmod 644 "$dst"
        echo "Wrote ${dst#"${REPO_DIR}/"} from the ${p} project — commit it, and every install that has it on gets it on its next pull." ;;
    offers)
        d="${REPO_DIR}/${FLOWS_DECREE%/.decree}/ai/proposed"; any=false
        for f in "$d"/*.md; do
            [[ -f "$f" ]] || continue; any=true; n="$(basename "$f" .md)"
            if plugin_is "$f"; then printf '  %-28s %s\n' "$n" "$(yq --front-matter=extract -r '.chart.description // ""' "$f" | cut -c1-90)"
            else printf '  %-28s %s\n' "$n" "a spec, not built yet: move it into notes/automations/ to have it built"; fi
        done
        if $any; then echo ""; echo "Read one in workspace/ai/proposed/, then:  ./existential.sh run plugin accept <name>"
        else echo "  Nothing is offered."; fi ;;
    accept)
        [[ -n "${1:-}" ]] || { echo "usage: plugin accept <name>   (./existential.sh run plugin offers lists them)" >&2; exit 2; }
        n="$1"; f="${REPO_DIR}/${FLOWS_DECREE%/.decree}/ai/proposed/${n}.md"
        die() { echo "plugin: $*" >&2; exit 1; }
        [[ "$n" =~ ^[a-z][a-z0-9_]{2,40}$ ]] || die "'${n}' is not a machine name"
        [[ -f "$f" ]] || die "nothing is offered as workspace/ai/proposed/${n}.md"
        plugin_is "$f" || die "${n} is a spec, not a plugin: move it into notes/automations/ and develop builds it for review"
        [[ "$(yq --front-matter=extract -r '.automation // ""' "$f")" == "$n" ]] || die "the file says 'automation: $(yq --front-matter=extract -r '.automation // ""' "$f")', not ${n}"
        [[ ! -f "${PLUGINS}/${n}.md" && ! -f "${PLUGINS}/flows/${n}.md" && "$PLUGIN_KERNEL" != *" ${n} "* ]] ||
            die "${n} is a plugin the repo ships, which nothing from the workspace replaces"
        for k in $(yq --front-matter=extract -r '.needs // [] | .[]' "$f"); do
            plugin_src "$PLUGINS" "$k" >/dev/null || die "it needs ${k}, which is no plugin here"
            plugin_in automation "$k" || die "it needs ${k}, which the automation project does not run"
        done
        echo ""
        echo "  ${n}: $(yq --front-matter=extract -r '.chart.description // ""' "$f")"
        yq --front-matter=extract -r '
            "  starts     " + ([(.when | select(.) | "on a note that is: " + .), (.handlers[]? | "when " + .match + " changes"),
                               (.cron // {} | keys | .[] | "cron " + .), (.endpoints[]? | "POST " + .path)] | join("; ") | select(. != "") // "only when something emits to it"),
            "  needs      " + ((.needs // []) | join(", ") | select(. != "") // "nothing"),
            "  scripts    " + ((.scripts // {}) | to_entries | map(.key + " (" + (.value | split("\n") | length | tostring) + " lines)") | join(", ")),
            "  lib        " + ((.lib // {}) | keys | join(", ") | select(. != "") // "none"),
            "  migrations " + ((.migrations // {}) | keys | join(", ") | select(. != "") // "none")' "$f"
        echo "  the file   workspace/ai/proposed/${n}.md"
        if [[ -f "${PLUGINS}/local/${n}.md" ]]; then
            echo ""; echo "  You accepted a ${n} before. What changes:"
            diff <(plugin_canon "${PLUGINS}/local/${n}.md" | yq -P) <(plugin_canon "$f" | yq -P) | sed 's/^/    /' | head -60 || true
        fi
        echo ""
        echo "  Its scripts run in the automation container, with that container's credentials."
        # A person, at a terminal: there is no flag that says yes for you.
        [[ -t 0 ]] || die "accept is a person's review, so it needs a terminal. Run it on the host yourself."
        read -r -p "  Have you read it, and should it be installed? [y/N] " reply || reply=""
        [[ "$reply" == [yY] || "$reply" == [yY][eE][sS] ]] || { echo "  Not installed."; exit 0; }
        mkdir -p "${PLUGINS}/local"
        cp "$f" "${PLUGINS}/local/${n}.md"; chmod 644 "${PLUGINS}/local/${n}.md"
        yq --front-matter=process -i '.project = "automation"' "${PLUGINS}/local/${n}.md"
        seed; plugins_turn on "$n"
        if ( sync_project automation ); then
            rm -f "$f"
            echo "  ${n} is installed and on. Off again:  ./existential.sh run plugin off ${n}"
        else
            plugins_turn off "$n"; rm -f "${PLUGINS}/local/${n}.md"; ( sync_project automation ) >/dev/null 2>&1 || true
            die "${n} did not install (above), so it is not kept. The offer is still in workspace/ai/proposed/."
        fi ;;
    seed)
        seed ;;
    *) echo "usage: plugin [list|on|off|sync|export|offers|accept|seed] ..." >&2; exit 2 ;;
esac
