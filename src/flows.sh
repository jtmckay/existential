#!/usr/bin/env bash
# flows.sh — turn the stack's curated flows on and off.
#
#   ./existential.sh flow                 pick in a terminal; a list otherwise
#   ./existential.sh flow list
#   ./existential.sh flow on <name>...    its services on, then its machine
#   ./existential.sh flow off <name>...   its machine off; services stay as they are
#
# A flow is a folder in flows/ (see src/utils/flows.sh for its shape). Turning
# one on turns on the flows it needs and the services they all name, unless the
# GPU answer forbids one, then copies in the cron files, migrations and file
# processors that start its machine. existential.sh renders and rebuilds after.
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

flows_on() {
    local want="$1" n v f vendor
    flow_exists "$want" || die "no flow '${want}' — ./existential.sh flow list"
    vendor="$(env_get EXIST_GPU_VENDOR)"
    for n in $(flow_closure "$want"); do
        for v in $(flow_list "$n" services); do
            [[ "$(env_get "$v")" == true ]] && continue
            if [[ -n "$vendor" ]] && vendor_forbids_service "$vendor" "$v"; then
                echo "  ${_D}↷ ${v} stays off — EXIST_GPU_VENDOR=${vendor}${_R}"; continue
            fi
            env_set "$v" true
            echo "  ${_G}✓${_R} ${v}=true"
        done
        while IFS= read -r f; do [[ -n "$f" ]] && echo "  ${_G}✓${_R} ${f}"; done < <(flow_activate "$n")
        [[ -f "${REPO_DIR}/${FLOWS_OFF}" ]] && sed -i "/^${n}\$/d" "${REPO_DIR}/${FLOWS_OFF}"
        [[ "$n" == "$want" ]] || echo "  ${_D}(${want} needs ${n}, so it is on too)${_R}"
    done
    echo ""
    echo "  ${_B}$(flow_get "$want" name)${_R} is on. $(flow_get "$want" tagline)"
    flow_body "$want" | sed 's/^/  /'
    echo "  More: https://existential.company$(flow_get "$want" docs)"
    echo ""
}

flows_off() {
    local n="$1" src dst
    flow_exists "$n" || die "no flow '${n}' — ./existential.sh flow list"
    while IFS=$'\t' read -r src dst; do
        [[ -e "${REPO_DIR}/${dst}" ]] || continue
        if cmp -s "${REPO_DIR}/${src}" "${REPO_DIR}/${dst}"; then
            rm -f "${REPO_DIR}/${dst}"; echo "  ✗ ${dst}"
        else
            echo "  kept ${dst}: you changed it, so delete it yourself if you mean to"
        fi
    done < <(flow_files "$n")
    if [[ "$(flow_get "$n" default)" == true ]]; then
        mkdir -p "$(dirname "${REPO_DIR}/${FLOWS_OFF}")"
        grep -qxF "$n" "${REPO_DIR}/${FLOWS_OFF}" 2>/dev/null || echo "$n" >> "${REPO_DIR}/${FLOWS_OFF}"
    fi
    echo ""
    echo "  $(flow_get "$n" name) is off. The services it turned on stay on; ./existential.sh service off <slug> turns one off."
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

case "${1:-}" in
    "")   if [[ -t 0 && -t 1 ]]; then flows_pick; else flows_list; exit 3; fi ;;
    list) flows_list; exit 3 ;;
    on)   shift; [[ $# -gt 0 ]] || die "which flow? ./existential.sh flow list"; for n in "$@"; do flows_on "$n"; done ;;
    off)  shift; [[ $# -gt 0 ]] || die "which flow? ./existential.sh flow list"; for n in "$@"; do flows_off "$n"; done ;;
    *)    die "usage: ./existential.sh flow [list | on <name>... | off <name>...]" ;;
esac
