#!/usr/bin/env bash
# flows.sh — turn the stack's curated flows on and off.
#
#   ./existential.sh flow                 pick in a terminal; a list otherwise
#   ./existential.sh flow list
#   ./existential.sh flow on <name>...    asks for each service it needs, then it is on
#   ./existential.sh flow off <name>...   its machine off; services stay as they are
#
# A flow is a plugin with no machine, automation/plugins/flows/<name>.md (see
# src/utils/flows.sh for its shape). Turning one on turns on the flows it needs
# and asks, one at a time, to turn on each service they name that is off (no
# answer is no; the GPU answer can forbid one), and puts it
# in the workspace's plugins.yml, the one record of what is on. existential.sh
# renders and rebuilds after, which installs it with everything it needs.
set -euo pipefail

# A REPO_DIR given wins: in adhoc, IN_CONTAINER alone would point a test's
# scratch repo at the real /repo.
if [[ -z "${REPO_DIR:-}" ]]; then
    if [[ -n "${IN_CONTAINER:-}" ]]; then REPO_DIR="/repo"; else REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; fi
fi
EXIST_ENV="${REPO_DIR}/.env.shared"

# shellcheck source=src/utils/flows.sh
. "${REPO_DIR}/src/utils/flows.sh"
# shellcheck source=src/utils/gpu-vendor.sh
. "${REPO_DIR}/src/utils/gpu-vendor.sh"

_G='' _D='' _B='' _R=''
[[ -t 1 ]] && _G=$'\033[32m' _D=$'\033[2m' _B=$'\033[1m' _R=$'\033[0m'
die() { echo "Error: $*" >&2; exit 1; }
[[ -f "$EXIST_ENV" ]] || die "${EXIST_ENV} not found — run ./existential.sh first"

env_get() { grep -E "^${1}=" "$EXIST_ENV" 2>/dev/null | head -1 | cut -d= -f2-; }
env_set() {
    if grep -qE "^${1}=" "$EXIST_ENV"; then sed -i "s|^${1}=.*|${1}=${2}|" "$EXIST_ENV"; else echo "${1}=${2}" >> "$EXIST_ENV"; fi
}

_row() {   # one line per flow: its id for the picker, then a mark, the id and the tagline
    local n="$1" mark="   "
    flow_on "$n" && mark="${_G}✓${_R}  "
    printf '%s\t%s%-20s %s%s%s\n' "$n" "$mark" "$n" "$_D" "$(flow_get "$n" tagline)" "$_R"
}

flows_list() {
    local n
    for n in $(flow_names); do _row "$n" | cut -f2-; done
    echo ""
    echo "  ./existential.sh flow on <name>"
}

# _slug <EXIST_IS_CAT_SLUG>: the slug `service on` takes.
_slug() { echo "$1" | sed 's/^EXIST_IS_[A-Z]*_//' | tr 'A-Z_' 'a-z-'; }

# _ask <question>: yes only for a typed y. No answer (no terminal, EOF) is no.
_ask() {
    local reply=""
    printf '  %s [y/N] ' "$1"
    IFS= read -r reply || true
    [[ -t 0 ]] || echo "$reply"
    [[ "$reply" == [yY] || "$reply" == [yY][eE][sS] ]]
}

flows_on() {
    local want="$1" n v vendor left=""
    flow_exists "$want" || die "no flow '${want}' — ./existential.sh flow list"
    vendor="$(env_get EXIST_GPU_VENDOR)"
    for n in $(flow_closure "$want"); do
        [[ "$n" == "$want" ]] || echo "  ${_D}(${want} needs ${n}, so it is on too)${_R}"
        for v in $(flow_list "$n" services); do
            [[ "$(env_get "$v")" == true ]] && continue
            if [[ -n "$vendor" ]] && vendor_forbids_service "$vendor" "$v"; then
                echo "  ${_D}↷ ${v} stays off — EXIST_GPU_VENDOR=${vendor}${_R}"; continue
            fi
            if _ask "${n} uses $(_slug "$v"), which is off. Turn it on?"; then
                env_set "$v" true
                echo "  ${_G}✓${_R} ${v}=true"
            else
                left+=" $(_slug "$v")"
            fi
        done
    done
    plugins_turn on "$want"
    echo ""
    echo "  ${_B}$(flow_get "$want" name)${_R} is on. $(flow_get "$want" tagline)"
    [[ -z "$left" ]] || echo "  It needs${left} to work, still off: ./existential.sh service on${left}"
    flow_body "$want" | sed 's/^/  /'
    echo "  More: https://existential.company$(flow_get "$want" docs)"
    echo ""
}

flows_off() {
    local n="$1"
    flow_exists "$n" || die "no flow '${n}' — ./existential.sh flow list"
    plugins_turn off "$n"
    echo ""
    echo "  $(flow_get "$n" name) is off: its plugins go on the next run, unless something still on needs them."
    echo "  The services it turned on stay on; ./existential.sh service off <slug> turns one off."
    echo ""
}

flows_pick() {
    command -v fzf >/dev/null 2>&1 || { flows_list; return 0; }
    local picked n
    picked="$(for n in $(flow_names); do _row "$n"; done | fzf --multi --ansi --delimiter=$'\t' --with-nth=2 \
        --layout=reverse --no-info --prompt="Flows ❯ " --bind 'space:toggle+down' \
        --header="  What should the stack do for you?   ${_G}✓${_R} = on
  Space marks a flow to switch (on → off, off → on)   Enter applies" | cut -f1)" || true
    [[ -n "$picked" ]] || { echo "  Nothing changed."; exit 3; }
    for n in $picked; do
        if flow_on "$n"; then flows_off "$n"; else flows_on "$n"; fi
    done
}

# An install from before plugins.yml gets one that keeps what it had on (plugin.sh seed).
if command -v yq >/dev/null 2>&1 && [[ ! -f "${REPO_DIR}/${PLUGINS_YML}" ]] && [[ -d "${REPO_DIR}/${FLOWS_DECREE}" ]]; then
    env REPO_DIR="$REPO_DIR" bash "${REPO_DIR}/src/lib/plugin.sh" seed automation >/dev/null
fi

case "${1:-}" in
    "")   if [[ -t 0 && -t 1 ]]; then flows_pick; else flows_list; exit 3; fi ;;
    list) flows_list; exit 3 ;;
    on)   shift; [[ $# -gt 0 ]] || die "which flow? ./existential.sh flow list"; for n in "$@"; do flows_on "$n"; done ;;
    off)  shift; [[ $# -gt 0 ]] || die "which flow? ./existential.sh flow list"; for n in "$@"; do flows_off "$n"; done ;;
    *)    die "usage: ./existential.sh flow [list | on <name>... | off <name>...]" ;;
esac
