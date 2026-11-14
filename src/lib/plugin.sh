#!/usr/bin/env bash
# plugin.sh — which of the repo's plugins (automation/plugins/) a decree project
# has on, and the sync that keeps them installed and current.
#
#   ./existential.sh run plugin [list] [project]
#   ./existential.sh run plugin on|off [project/]<name>
#   ./existential.sh run plugin sync [project] [name...]
#   ./existential.sh run plugin export [project/]<name>
#
# project is automation (the default), backup or host. Each project's
# .decree/plugins.yml is the one record of what it has on, written from its
# plugins.exist.yml the first time. on/off edit it; sync installs what is on and
# what that needs, the new version of what changed, and removes what is no
# longer wanted (lib/automations/plugin.sh). A flow is a plugin in
# automation/plugins/flows/; ./existential.sh flow is the same list, for flows.
# export writes an installed plugin back to its file in automation/plugins/.
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

# Each project's first plugins.yml.
seed_of() {
    case "$1" in
        automation) echo "${REPO_DIR}/automation/plugins.exist.yml" ;;
        backup)     echo "${REPO_DIR}/services/automation-backup/plugins.exist.yml" ;;
        host)       echo "${REPO_DIR}/automation/plugins.host.exist.yml" ;;
    esac
}

# Enter the project: its root is the directory whose .decree/ it is.
enter() {  # <project> [ro: only look, so a missing project is an empty one]
    case "$1" in
        automation) if [[ -d "${REPO_DIR}/${FLOWS_DECREE}" || -z "${2:-}" ]]; then
                        mkdir -p "${REPO_DIR}/${FLOWS_DECREE}"; cd "${REPO_DIR}/${FLOWS_DECREE%/.decree}"
                    else cd "$(mktemp -d)"; fi ;;
        # The host's own project (gitignored), for what runs on the host itself:
        # not the repo's .decree/, which is for developing this repo.
        host)       mkdir -p "${REPO_DIR}/host/.decree"; cd "${REPO_DIR}/host" ;;
        backup)     # services/automation-backup/ is itself the project, mounted as .decree.
                    local root; root="$(mktemp -d)"
                    ln -s "${REPO_DIR}/services/automation-backup" "${root}/.decree"
                    cd "$root" ;;
        *) echo "plugin: no project '$1' (automation, backup or host)" >&2; exit 2 ;;
    esac
    export DECREE_RUN_DIR; DECREE_RUN_DIR="$(mktemp -d)"
    seed "$1"
}

# plugins.yml, from the project's example, once. An install from before plugins
# keeps what it had: a flow whose cron or migration is already in the project is
# on, and a default flow it had turned off (flows-off) stays off.
seed() {  # <project>
    local cfg=.decree/plugins.yml f n k
    [[ -f "$cfg" || ! -d .decree ]] && return 0
    cp "$(seed_of "$1")" "$cfg"
    [[ "$1" == automation ]] || return 0
    for f in "$PLUGINS"/flows/*.md; do
        n="$(basename "$f" .md)"
        for k in $(yq --front-matter=extract -r '((.cron // {}) | keys | .[] | "cron/" + . + ".md"), ((.migrations // {}) | keys | .[] | "migrations/" + . + ".md")' "$f"); do
            if [[ -e ".decree/${k}" ]] || grep -qxF "${k#migrations/}" .decree/processed.md 2>/dev/null; then
                n="$n" yq -i '.on = ((.on // []) + [strenv(n)] | unique)' "$cfg"; break
            fi
        done
    done
    if [[ -f .decree/flows-off ]]; then
        while IFS= read -r n; do [[ -n "$n" ]] && n="$n" yq -i '.on -= [strenv(n)]' "$cfg"; done < .decree/flows-off
        rm -f .decree/flows-off
    fi
}

# [project/]name → "project name"
split() { if [[ "$1" == */* ]]; then echo "${1%%/*} ${1#*/}"; else echo "automation $1"; fi; }

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

# The plugin system follows the checkout: automation/machines/ and scripts/ are
# copied over every time, and each of its endpoints the project lacks is added.
# backup gets notify alone: every plugin may tell you something, and sharing
# plugins is the automation project's. host gets none: ntfy is on the docker
# network, so a host plugin tells you through the automation container.
kernel() {  # <project>
    local path
    mkdir -p .decree/machines .decree/scripts
    [[ "$1" != host ]] || return 0
    shared_lib
    if [[ "$1" != automation ]]; then
        cp -p "${REPO_DIR}/automation/machines/notify.yml" .decree/machines/
        cp -p "${REPO_DIR}/automation/scripts/notify.sh" .decree/scripts/
        return 0
    fi
    cp -p "${REPO_DIR}"/automation/machines/*.yml .decree/machines/
    cp -rp "${REPO_DIR}"/automation/scripts/. .decree/scripts/
    [[ -f "$REST" ]] || return 0
    for path in $(yq -r '.endpoints[] | select(.message.machine | test("^(plugin|plugin_[a-z]+|notify)$")) | .path' "${REPO_DIR}/automation/decree-go-rest.exist.yml"); do
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
        p="${1:-automation}"; enter "$p" ro
        wanted=" $(plugin_wanted "$PLUGINS" "$p" 2>/dev/null | tr '\n' ' ') "
        for f in "$PLUGINS"/*.md "$PLUGINS"/flows/*.md; do
            n="$(basename "$f" .md)"
            mark=" "; [[ "$wanted" == *" ${n} "* ]] && mark="on"
            automation_installed "$n" && mark="${mark/ /} ✓"
            printf '  %-4s %-28s %s\n' "$mark" "$n" "$(yq --front-matter=extract -r '.tagline // .chart.description // ""' "$f" | cut -c1-90)"
        done
        echo ""; echo "✓ installed in ${p}. Turn one on:  ./existential.sh run plugin on [${p}/]<name>" ;;
    on|off)
        [[ -n "${1:-}" ]] || { echo "usage: plugin ${cmd} [project/]<name>" >&2; exit 2; }
        read -r p n <<<"$(split "$1")"
        plugin_src "$PLUGINS" "$n" >/dev/null || { echo "plugin: no ${n} in automation/plugins/" >&2; exit 1; }
        ( enter "$p"; cfg=.decree/plugins.yml
          if [[ "$cmd" == on ]]; then n="$n" yq -i '.on = ((.on // []) + [strenv(n)] | unique)' "$cfg"
          else                        n="$n" yq -i '.on = ((.on // []) - [strenv(n)])' "$cfg"; fi )
        sync_project "$p" ;;
    sync)
        sync_project "${1:-automation}" "${@:2}" ;;
    export)
        [[ -n "${1:-}" ]] || { echo "usage: plugin export [project/]<name>" >&2; exit 2; }
        read -r p n <<<"$(split "$1")"
        enter "$p"
        dst="$(plugin_src "$PLUGINS" "$n" || echo "${PLUGINS}/${n}.md")"
        out="$(mktemp)"; plugin_export "$n" > "$out"
        mv "$out" "$dst"; chmod 644 "$dst"
        echo "Wrote ${dst#"${REPO_DIR}/"} — commit it, and every install that has it on gets it on its next pull." ;;
    seed)
        enter "${1:-automation}" ;;
    *) echo "usage: plugin [list|on|off|sync|export|seed] ..." >&2; exit 2 ;;
esac
