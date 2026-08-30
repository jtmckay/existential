#!/usr/bin/env bash
# footprint.sh — how much memory a selection of services can ever use.
#
#   ./existential.sh run footprint            # what you have enabled
#   ./existential.sh run footprint core       # what the Core quest asks for
#   ./existential.sh run footprint all        # every service in the repo
#
# Every container declares a `deploy.resources.limits.memory`, sized at roughly
# 2-3x what that service actually uses. Docker does not set anything aside — the
# limit only says when the kernel starts pushing back.
#
# And "pushing back" is gentler than it sounds. Docker sets memory.swap.max equal
# to memory.max, so a container gets its limit in RAM *and the same again in
# swap* before anything is OOM-killed. A service that drifts over its limit has
# its cold pages swapped out, which for a homelab is exactly right: the box stays
# up, the rarely-touched memory goes to disk, and nothing dies.
#
# Both numbers matter and they answer different questions:
#   limit    when does the kernel start pushing this service into swap?
#   in use   what is it actually costing right now?
#
# So both are shown. The ceiling comes from the templates and covers services you
# have never started; "in use" comes from `docker stats` and only covers what is
# running right now. A service with a ceiling and no usage figure is one you have
# not turned on — which is exactly the gap this tool exists to close, because
# "what will happen if I enable this" has no other answer.
set -euo pipefail

if [[ -n "${IN_CONTAINER:-}" ]]; then
    REPO_DIR="/repo"
else
    REPO_DIR="${REPO_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
fi
SCRIPT_DIR="$REPO_DIR"

# shellcheck source=../utils/service-common.sh
. "${REPO_DIR}/src/utils/service-common.sh"

MODE="${1:-enabled}"
CORE_QUEST="${REPO_DIR}/src/quests/00-core.md"

_C_RESET=$'\033[0m'; _C_BOLD=$'\033[1m'; _C_DIM=$'\033[2m'
_C_GREEN=$'\033[32m'; _C_YELLOW=$'\033[33m'; _C_CYAN=$'\033[36m'

# Bytes for a compose memory value (512M, 2G, 1073741824).
_to_mib() {
    local v="${1:-0}" n unit
    n="${v%[A-Za-z]*}"; unit="${v#"$n"}"
    case "${unit^^}" in
        G|GB) awk -v n="$n" 'BEGIN{printf "%d", n*1024}' ;;
        M|MB) awk -v n="$n" 'BEGIN{printf "%d", n}' ;;
        K|KB) awk -v n="$n" 'BEGIN{printf "%d", n/1024}' ;;
        "")   awk -v n="$n" 'BEGIN{printf "%d", n/1048576}' ;;
        *)    echo 0 ;;
    esac
}

_fmt() { awk -v m="$1" 'BEGIN{ if (m>=1024) printf "%.1f GiB", m/1024; else printf "%d MiB", m }'; }

# container → MiB in use, for everything running now. One docker call, not one
# per container: on a 65-container stack the per-container form is slow enough
# to look hung.
declare -A INUSE=()
HAVE_STATS=0
if command -v docker >/dev/null 2>&1; then
    while IFS=$'\t' read -r _n _u; do
        [[ -n "$_n" ]] || continue
        INUSE["$_n"]="$(awk -v v="$_u" 'BEGIN{
            n=v+0
            if (v ~ /GiB/) n*=1024
            else if (v ~ /KiB/) n/=1024
            printf "%d", n
        }')"
        HAVE_STATS=1
    done < <(docker stats --no-stream --format '{{.Name}}\t{{.MemUsage}}' 2>/dev/null \
             | awk -F'\t' '{split($2,a," "); print $1"\t"a[1]}')
fi

# Emit "container<TAB>limit" for every container in a service directory.
_containers_in() {
    local tmpl="$1/docker-compose.exist.yml"
    [[ -f "$tmpl" ]] || return 0
    python3 - "$tmpl" <<'PY'
import sys, re
s = open(sys.argv[1]).read()
body = s.split('\nservices:', 1)[-1]
for b in re.split(r'\n  (?=[a-z0-9][a-z0-9_-]*:\s*$)', body, flags=re.M):
    cn = re.search(r'container_name:\s*(\S+)', b)
    if not cn:
        continue
    mem = re.search(r'memory:\s*(\S+)', b)
    print(f"{cn.group(1)}\t{mem.group(1) if mem else '?'}")
PY
}

# Which services are in scope, as absolute directories.
_selected_dirs() {
    local dir
    case "$MODE" in
        all)
            _find_service_dirs
            ;;
        core)
            # The Core quest's own service list is the source of truth — the
            # same list quest ticks — so this can never drift from what Core
            # actually installs.
            local -a vars=()
            mapfile -t vars < <(awk '/^services:/{f=1;next} /^copies:/{f=0} f && /var:/{print $3}' "$CORE_QUEST")
            for dir in $(_find_service_dirs); do
                local v; v="$(_enable_var_for "$dir")"
                printf '%s\n' "${vars[@]}" | grep -qx "$v" && echo "$dir"
            done
            ;;
        enabled)
            for dir in $(_find_service_dirs); do
                service_is_enabled "$dir" && echo "$dir"
            done
            ;;
        *)
            echo "Unknown mode '${MODE}' — use: enabled | core | all" >&2
            exit 1
            ;;
    esac
}

case "$MODE" in
    all)     _title="every service in the repository" ;;
    core)    _title="the Core quest" ;;
    enabled) _title="your enabled services" ;;
esac

echo ""
echo "  ${_C_BOLD}Memory — ${_title}${_C_RESET}"
if [[ "$HAVE_STATS" == "1" ]]; then
    echo "  ${_C_DIM}limit = where swapping starts (2x that with swap);  in use = right now.${_C_RESET}"
    echo ""
    printf '  %-26s %3s %10s %10s\n' "" "n" "limit" "in use"
else
    echo "  ${_C_DIM}Where each container starts being pushed into swap.${_C_RESET}"
    echo ""
fi

TOTAL=0; COUNT=0; UNLIMITED=0; USED=0; USED_N=0
OLLAMA_MIB=0; OLLAMA_N=0; OLLAMA_USED=0
declare -a ROWS=()

while IFS= read -r dir; do
    [[ -n "$dir" ]] || continue
    local_total=0; local_n=0; local_used=0; local_used_n=0
    while IFS=$'\t' read -r cn mem; do
        [[ -n "$cn" ]] || continue
        if [[ "$mem" == "?" ]]; then
            UNLIMITED=$((UNLIMITED + 1))
            ROWS+=("$(printf '%-30s %s?%s' "$cn" "$_C_YELLOW" "$_C_RESET")")
            continue
        fi
        mib="$(_to_mib "$mem")"
        local_total=$((local_total + mib)); local_n=$((local_n + 1))
        TOTAL=$((TOTAL + mib)); COUNT=$((COUNT + 1))
        # ollama is called out separately: it is the single biggest line, and
        # the whole point of the `external` GPU vendor is not running it here.
        if [[ "$dir" == */ai/ollama ]]; then
            OLLAMA_MIB=$((OLLAMA_MIB + mib)); OLLAMA_N=$((OLLAMA_N + 1))
            OLLAMA_USED=$((OLLAMA_USED + ${INUSE[$cn]:-0}))
        fi
        if [[ -n "${INUSE[$cn]:-}" ]]; then
            local_used=$((local_used + INUSE[$cn]))
            local_used_n=$((local_used_n + 1))
            USED=$((USED + INUSE[$cn])); USED_N=$((USED_N + 1))
        fi
    done < <(_containers_in "$dir")
    [[ "$local_n" -gt 0 ]] || continue
    if [[ "$HAVE_STATS" == "1" ]]; then
        if [[ "$local_used_n" -gt 0 ]]; then
            printf '  %-26s %3d %10s %10s\n' "${dir#"$REPO_DIR"/}" "$local_n" \
                "$(_fmt "$local_total")" "$(_fmt "$local_used")"
        else
            printf '  %-26s %3d %10s %10s\n' "${dir#"$REPO_DIR"/}" "$local_n" \
                "$(_fmt "$local_total")" "${_C_DIM}not running${_C_RESET}"
        fi
    else
        printf '  %-26s %3d %10s\n' "${dir#"$REPO_DIR"/}" "$local_n" "$(_fmt "$local_total")"
    fi
done < <(_selected_dirs)

echo ""
if [[ "$HAVE_STATS" == "1" ]]; then
    printf '  %-26s %3d %10s %10s\n' "${_C_BOLD}TOTAL${_C_RESET}" "$COUNT" \
        "${_C_BOLD}$(_fmt "$TOTAL")${_C_RESET}" "${_C_BOLD}$(_fmt "$USED")${_C_RESET}"
    printf '  %-26s %3s %10s %10s\n' "${_C_DIM}(of which running)${_C_RESET}" "$USED_N" "" ""
else
    printf '  %-26s %3d %10s\n' "${_C_BOLD}TOTAL${_C_RESET}" "$COUNT" "${_C_BOLD}$(_fmt "$TOTAL")${_C_RESET}"
fi

if [[ "$OLLAMA_MIB" -gt 0 ]]; then
    printf '  %-26s %3d %10s\n' "${_C_CYAN}without ollama${_C_RESET}" \
        "$((COUNT - OLLAMA_N))" "${_C_CYAN}$(_fmt "$((TOTAL - OLLAMA_MIB))")${_C_RESET}"
    echo ""
    echo "  ${_C_DIM}ollama is $(_fmt "$OLLAMA_MIB") of that. Set EXIST_GPU_VENDOR=external and point${_C_RESET}"
    echo "  ${_C_DIM}EXIST_OLLAMA_URL at another box to move it off this machine entirely.${_C_RESET}"
fi

if [[ "$UNLIMITED" -gt 0 ]]; then
    echo ""
    echo "  ${_C_YELLOW}⚠${_C_RESET}  ${UNLIMITED} container(s) declare no memory limit — the ceiling above"
    echo "     understates the real worst case. Add one to their template."
    printf '     %s\n' "${ROWS[@]}"
fi

# What the box actually has, when we can see it. A ceiling means nothing without
# it, and "will this fit" is the only question anyone is really asking.
if [[ -r /proc/meminfo ]]; then
    HOST_MIB=$(awk '/^MemTotal:/{printf "%d", $2/1024}' /proc/meminfo)
    echo ""
    printf '  This machine has %s of RAM.\n' "$(_fmt "$HOST_MIB")"
    if [[ "$TOTAL" -gt "$HOST_MIB" ]]; then
        echo "  ${_C_YELLOW}The limits add up to more than that.${_C_RESET} Usually fine: services do not all"
        echo "  sit at their limit, and one that does gets swapped rather than killed."
        echo "  The number that matters is the in-use column. Watch it with:"
        echo "    docker stats --no-stream"
    else
        echo "  ${_C_GREEN}Every limit fits at once, without touching swap.${_C_RESET}"
    fi
fi
echo ""
