#!/usr/bin/env bash
# fix-permissions.sh — reclaim paths this user cannot write, and restore the
# file modes a fresh checkout would have.
#
#   ./existential.sh run fix-permissions [--dry-run]
#
# Why a checkout ends up needing this: when a bind-mount source path does not
# exist, the Docker daemon creates it — as an empty root:root directory. Every
# `docker compose up` that beats the renderer to a path leaves one behind, and
# from then on the render fails ("rm: Permission denied"), reset fails on its
# first mkdir, and the container that mounted it sees an empty directory where
# the image had files. generate-compose.ts now pre-creates those sources as the
# host user, so new ones stop appearing; this is the repair for the ones that
# already exist.
#
# Reclaiming needs root, which we borrow from a throwaway container rather than
# asking for sudo — the same trick e2e.sh uses to clean up after itself.
#
# This command NEVER deletes anything. It changes ownership and mode only.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

DRY_RUN=false
for _arg in "$@"; do
    case "$_arg" in
        --dry-run|-n) DRY_RUN=true ;;
        --help|-h)
            sed -n '2,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *) echo "Unknown option: ${_arg}" >&2; exit 1 ;;
    esac
done

DOCKER_CMD="${DOCKER_CMD:-docker}"
command -v "$DOCKER_CMD" >/dev/null 2>&1 || {
    echo "Error: ${DOCKER_CMD} not found on PATH — this command borrows root from a container." >&2
    exit 1
}

_C_GREEN=$'\033[32m'
_C_YELLOW=$'\033[33m'
_C_DIM=$'\033[2m'
_C_BOLD=$'\033[1m'
_C_RESET=$'\033[0m'

hr() { printf '%0.s─' {1..64}; echo; }

UID_NOW="$(id -u)"
GID_NOW="$(id -g)"

# ── What is not ours ──────────────────────────────────────────────────────────

# Roll a sorted path list up to its shallowest entries: if ai/hermes/hermes_install
# is foreign then so is everything beneath it, and one line says more than four
# hundred. Sorted input guarantees a parent precedes its children, so a running
# prefix check is enough.
_roots() {
    awk 'BEGIN { cur = "" }
         NF == 0 { next }
         { if (cur != "" && index($0, cur "/") == 1) next; cur = $0; print }'
}

mapfile -t FOREIGN < <(
    find "$REPO_DIR" -path "${REPO_DIR}/.git" -prune -o \
         -not -user "$UID_NOW" -printf '%P\n' 2>/dev/null | sort | _roots
)

# ── What has the wrong mode ───────────────────────────────────────────────────

# git tracks exactly one permission bit, so that is the only one restored. The
# rest (group-write from a 002 umask, for instance) is the user's business, and
# forcing a literal 644 would quietly undo it.
#
# Every branch below ends in a true command on purpose: a bare `[[ ... ]] &&`
# as the last statement of a loop body returns 1 when the test is false, and
# under `set -e` that ends the subshell — silently truncating the list at the
# first well-behaved file.
mapfile -t MODE_FIX < <(
    cd "$REPO_DIR" || exit 0
    git ls-files -s 2>/dev/null | while read -r mode _ _ file; do
        [[ -f "$file" ]] || continue
        if [[ "$mode" == 100755 && ! -x "$file" ]]; then
            printf '+x\t%s\n' "$file"
        elif [[ "$mode" == 100644 && -x "$file" ]]; then
            printf -- '-x\t%s\n' "$file"
        fi
    done
    :
)

TOTAL=$(( ${#FOREIGN[@]} + ${#MODE_FIX[@]} ))

echo ""
hr
echo "  ${_C_BOLD}Fix permissions${_C_RESET}"
hr
echo ""
echo "  Repo: ${REPO_DIR}"
echo ""

if [[ "$TOTAL" -eq 0 ]]; then
    echo "  ${_C_GREEN}✓${_C_RESET}  Nothing to fix — every path is owned by ${UID_NOW}:${GID_NOW}"
    echo "     and every tracked file has the mode a fresh checkout would give it."
    echo ""
    exit 0
fi

# ── Show ──────────────────────────────────────────────────────────────────────

_has_volumes=false
if [[ "${#FOREIGN[@]}" -gt 0 ]]; then
    echo "  ${_C_BOLD}Owned by another user${_C_RESET} (${#FOREIGN[@]}) — will be given to ${UID_NOW}:${GID_NOW}, recursively:"
    echo ""
    for _p in "${FOREIGN[@]}"; do
        case "$_p" in volumes/*|volumes) _has_volumes=true ;; esac
        printf '    %-46s %s%s%s\n' "$_p" \
            "$_C_DIM" "$(stat -c '%U:%G' "${REPO_DIR}/${_p}" 2>/dev/null)" "$_C_RESET"
    done
    echo ""
fi

if [[ "${#MODE_FIX[@]}" -gt 0 ]]; then
    echo "  ${_C_BOLD}Mode differs from git${_C_RESET} (${#MODE_FIX[@]}) — only the executable bit is touched:"
    echo ""
    printf '    %s\n' "${MODE_FIX[@]}"
    echo ""
fi

# ── The warning that actually matters ─────────────────────────────────────────

if $_has_volumes; then
    echo "  ${_C_YELLOW}⚠  This includes your data directories.${_C_RESET}"
    echo "     Some containers legitimately run as root and own their data on purpose —"
    echo "     postgres refuses to start if its pgdata is owned by anyone else, and Home"
    echo "     Assistant is much the same. Changing ownership underneath them can stop"
    echo "     them coming back up."
    echo ""
    echo "     Nothing is deleted either way, and re-running a container's own setup"
    echo "     usually re-fixes its data. But bring the stack down first:"
    echo ""
    echo "       docker compose down"
    echo ""
fi

if [[ -n "$($DOCKER_CMD ps -q 2>/dev/null)" ]]; then
    echo "  ${_C_YELLOW}⚠  Containers are running right now.${_C_RESET} Chowning files underneath a"
    echo "     running container is how you get a service that works until its next"
    echo "     restart. Consider: docker compose down"
    echo ""
fi

if $DRY_RUN; then
    echo "  ${_C_DIM}--dry-run — nothing was changed.${_C_RESET}"
    echo ""
    exit 0
fi

read -rp "  Fix ${TOTAL} item(s)? [y/N] " _confirm
if [[ "${_confirm,,}" != "y" && "${_confirm,,}" != "yes" ]]; then
    echo ""
    echo "  Nothing changed."
    echo ""
    exit 0
fi

# ── Reclaim ───────────────────────────────────────────────────────────────────

_rc=0

if [[ "${#FOREIGN[@]}" -gt 0 ]]; then
    echo ""
    echo "  Reclaiming ownership (root container)..."
    # NUL-delimited so a path with a space survives, and so the argument list is
    # never a limit. busybox xargs in alpine handles -0.
    if printf '/repo/%s\0' "${FOREIGN[@]}" \
        | $DOCKER_CMD run --rm -i -u 0 -v "${REPO_DIR}:/repo" alpine \
              sh -c "xargs -0 chown -R ${UID_NOW}:${GID_NOW} --"
    then
        echo "  ${_C_GREEN}✓${_C_RESET}  ${#FOREIGN[@]} path(s) reclaimed."
    else
        echo "  ${_C_YELLOW}✗${_C_RESET}  Could not reclaim ownership." >&2
        _rc=1
    fi
fi

if [[ "${#MODE_FIX[@]}" -gt 0 ]]; then
    echo "  Restoring tracked file modes..."
    _n=0
    for _line in "${MODE_FIX[@]}"; do
        _op="${_line%%	*}"; _file="${_line#*	}"
        if chmod "${_op/-x/a-x}" "${REPO_DIR}/${_file}" 2>/dev/null; then
            _n=$(( _n + 1 ))
        else
            echo "  ${_C_YELLOW}could not chmod${_C_RESET} ${_file}" >&2
        fi
    done
    echo "  ${_C_GREEN}✓${_C_RESET}  ${_n} mode(s) restored."
fi

echo ""
if [[ "$_rc" -eq 0 ]]; then
    echo "  Next:  ./existential.sh        (renders, and re-extracts any build caches)"
    echo "         docker compose up -d"
else
    echo "  Some items could not be fixed — re-run to see what is left."
fi
echo ""
exit "$_rc"
