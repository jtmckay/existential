#!/usr/bin/env bash
# services.sh — turn single services on and off, so .env.shared needn't be opened.
#
#   ./existential.sh service                  pick in a terminal; a list otherwise
#   ./existential.sh service list
#   ./existential.sh service on <slug>...     its EXIST_IS_* flag to true
#   ./existential.sh service off <slug>...    its EXIST_IS_* flag to false
#
# A service is a folder (<category>/<slug>), so this is only its flag. A flow
# turns on everything it needs; this is for the rest. existential.sh renders and
# rebuilds after. Exits 3 for "nothing changed", as src/flows.sh does.
set -euo pipefail

if [[ -z "${REPO_DIR:-}" ]]; then
    if [[ -n "${IN_CONTAINER:-}" ]]; then REPO_DIR="/repo"; else REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; fi
fi
SCRIPT_DIR="$REPO_DIR"
EXIST_ENV="${REPO_DIR}/.env.shared"

# shellcheck source=src/utils/service-common.sh
. "${REPO_DIR}/src/utils/service-common.sh"
# shellcheck source=src/utils/gpu-vendor.sh
. "${REPO_DIR}/src/utils/gpu-vendor.sh"

_G='' _D='' _R=''
[[ -t 1 ]] && _G=$'\033[32m' _D=$'\033[2m' _R=$'\033[0m'
die() { echo "Error: $*" >&2; exit 1; }
[[ -f "$EXIST_ENV" ]] || die "${EXIST_ENV} not found — run ./existential.sh first"

env_get() { grep -E "^${1}=" "$EXIST_ENV" 2>/dev/null | head -1 | cut -d= -f2-; }
env_set() {
    if grep -qE "^${1}=" "$EXIST_ENV"; then sed -i "s|^${1}=.*|${1}=${2}|" "$EXIST_ENV"; else echo "${1}=${2}" >> "$EXIST_ENV"; fi
}
svc_on() { [[ "$(env_get "$(_enable_var_for "$1")")" == true ]]; }

# svc_dir <slug or category/slug> — the service's folder, or fail.
svc_dir() {
    local d
    while IFS= read -r d; do
        [[ "${d##*/}" == "$1" || "${d#"$REPO_DIR"/}" == "$1" ]] && { echo "$d"; return 0; }
    done < <(_find_service_dirs)
    die "no service '$1' — ./existential.sh service list"
}

_row() {   # its folder for the picker, then a mark and category/slug
    local mark="   "
    svc_on "$1" && mark="${_G}✓${_R}  "
    printf '%s\t%s%s\n' "$1" "$mark" "${1#"$REPO_DIR"/}"
}

services_list() {
    local d
    while IFS= read -r d; do _row "$d" | cut -f2-; done < <(_find_service_dirs)
    echo ""
    echo "  ./existential.sh service on <slug>"
}

services_on() {
    local var vendor
    var="$(_enable_var_for "$1")"
    vendor="$(env_get EXIST_GPU_VENDOR)"
    if [[ -n "$vendor" ]] && vendor_forbids_service "$vendor" "$var"; then
        echo "  ${_D}↷ ${var} stays off — EXIST_GPU_VENDOR=${vendor} (./existential.sh run models)${_R}"
        return 0
    fi
    env_set "$var" true
    echo "  ${_G}✓${_R} ${var}=true"
}

services_off() {
    local var; var="$(_enable_var_for "$1")"
    env_set "$var" false
    echo "  ✗ ${var}=false"
    _turned_off=1
}

services_pick() {
    command -v fzf >/dev/null 2>&1 || { services_list; exit 3; }
    local picked d
    picked="$(while IFS= read -r d; do _row "$d"; done < <(_find_service_dirs) \
        | fzf --multi --ansi --delimiter=$'\t' --with-nth=2 \
        --layout=reverse --no-info --prompt="Services ❯ " --bind 'space:toggle+down' \
        --header="  Which services run?   ${_G}✓${_R} = on
  Space marks a service to switch (on → off, off → on)   Enter applies" | cut -f1)" || true
    [[ -n "$picked" ]] || { echo "  Nothing changed."; exit 3; }
    while IFS= read -r d; do
        if svc_on "$d"; then services_off "$d"; else services_on "$d"; fi
    done <<< "$picked"
}

_turned_off=0
case "${1:-}" in
    "")   if [[ -t 0 && -t 1 ]]; then services_pick; else services_list; exit 3; fi ;;
    list) services_list; exit 3 ;;
    on)   shift; [[ $# -gt 0 ]] || die "which service? ./existential.sh service list"
          for s in "$@"; do d="$(svc_dir "$s")"; services_on "$d"; done ;;
    off)  shift; [[ $# -gt 0 ]] || die "which service? ./existential.sh service list"
          for s in "$@"; do d="$(svc_dir "$s")"; services_off "$d"; done ;;
    *)    die "usage: ./existential.sh service [list | on <slug>... | off <slug>...]" ;;
esac

# Compose leaves a removed service's containers running; this is what stops them.
if [[ "$_turned_off" == 1 ]]; then
    echo ""
    echo "  Its containers keep running until:  docker compose up -d --remove-orphans"
fi
echo ""
