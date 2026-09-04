#!/usr/bin/env bash
# reset.sh — archive everything existential rendered, so the next run starts clean.
#
#   ./existential.sh reset
#
# This replaces the old `--force`. That flag re-rendered over your files with no
# undo, and "force" never said what it would touch. Reset says exactly what it
# will move, moves it into archive/<timestamp>/ with paths preserved, and leaves
# the next `./existential.sh` to render everything fresh.
#
# CONFIG ONLY. Volumes are never touched — not moved, not copied, not deleted.
# Your files, photos, databases and models stay exactly where they are. The one
# thing reset does about data is tell you where it lives.
#
# Restoring is a copy, because the archive mirrors the repo layout:
#     cp -r archive/<timestamp>/. .

set -euo pipefail

# An explicitly-set REPO_DIR always wins. The usual pattern in this repo checks
# IN_CONTAINER first and hard-assigns /repo, which is fine for read-only scripts
# but wrong here: this command MOVES files, and silently retargeting it at /repo
# when a caller asked for somewhere else is how you archive the wrong tree.
if [[ -z "${REPO_DIR:-}" ]]; then
    if [[ -n "${IN_CONTAINER:-}" ]]; then
        REPO_DIR="/repo"
    else
        REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
    fi
fi

# Refuse to run anywhere that is not an existential checkout. Cheap insurance
# against a mistyped REPO_DIR turning into a recursive move of someone's home.
for _marker in .env.exist.shared src/templates.sh; do
    [[ -e "${REPO_DIR}/${_marker}" ]] || {
        echo "Error: ${REPO_DIR} does not look like an existential repo (no ${_marker})." >&2
        exit 1
    }
done

_C_GREEN=$'\033[32m'
_C_YELLOW=$'\033[33m'
_C_BOLD=$'\033[1m'
_C_RESET=$'\033[0m'

hr() { printf '%0.s─' {1..64}; echo; }

# _template_to_dst is the single source of truth for where a template renders.
# templates.sh guards its _main, so sourcing loads the functions without
# rendering anything — reset can never disagree with the renderer about paths.
SCRIPT_DIR="${REPO_DIR}"
# shellcheck source=src/templates.sh
. "${REPO_DIR}/src/templates.sh"

# ── What exists on disk that existential put there ────────────────────────────

# Rendered template outputs, for EVERY service — not just the enabled ones. A
# service turned off after being rendered still has files on disk, and those are
# exactly the stale ones a reset is for.
_rendered_files() {
    local src dst
    while IFS= read -r src; do
        dst="$(_template_to_dst "$src")"
        [[ -n "$dst" && -e "$dst" ]] && printf '%s\n' "${dst#"$REPO_DIR/"}"
    done < <(find "$REPO_DIR" \( -name '*.exist.*' -o -name '*.env.exist' \) \
                 -not -path '*/graveyard/*' -not -path '*/.git/*' \
                 -not -path '*/node_modules/*' -not -path '*/site/*' \
                 -not -path "*/archive/*" 2>/dev/null | sort)
}

# Generated at the repo root rather than rendered from a template.
_generated_files() {
    local f
    for f in docker-compose.yml .env.shared .env; do
        [[ -e "${REPO_DIR}/${f}" ]] && printf '%s\n' "$f"
    done
    # Old compose archives, from before archiving moved under archive/.
    while IFS= read -r f; do
        printf '%s\n' "${f#"$REPO_DIR/"}"
    done < <(find "$REPO_DIR" -maxdepth 1 -name 'docker-compose-*.yml' 2>/dev/null | sort)
}

# Cron and migration templates the user activated by copying them out of
# cron.example/ and migrations.example/. The examples themselves are tracked and
# never touched; only the activated copies are.
_activated_files() {
    local f
    while IFS= read -r f; do
        printf '%s\n' "${f#"$REPO_DIR/"}"
    done < <(find "$REPO_DIR" \( -path '*/automation/cron/*' -o -path '*/automation/migrations/*' \
                                -o -path '*/backup/cron/*' \) \
                 -name '*.md' -type f \
                 -not -path '*/graveyard/*' -not -path '*/node_modules/*' 2>/dev/null | sort)
}

# ── Collect ───────────────────────────────────────────────────────────────────

mapfile -t RENDERED  < <(_rendered_files)
mapfile -t GENERATED < <(_generated_files)
mapfile -t ACTIVATED < <(_activated_files)

TOTAL=$(( ${#RENDERED[@]} + ${#GENERATED[@]} + ${#ACTIVATED[@]} ))

echo ""
hr
echo "  ${_C_BOLD}Reset — archive rendered config${_C_RESET}"
hr
echo ""
echo "  Repo: ${REPO_DIR}"
echo ""

if [[ "$TOTAL" -eq 0 ]]; then
    echo "  Nothing to archive — no rendered config on disk."
    echo "  Run ./existential.sh to render it."
    echo ""
    exit 0
fi

# Show every path. A reset that hides what it is moving behind a count is the
# thing this command exists to replace.
_show() {
    local title="$1"; shift
    [[ "$#" -eq 0 ]] && return 0
    echo "  ${title} (${#}):"
    printf '    %s\n' "$@"
    echo ""
}

_show "Rendered from templates"      ${RENDERED[@]+"${RENDERED[@]}"}
_show "Generated"                    ${GENERATED[@]+"${GENERATED[@]}"}
_show "Activated cron / migrations"  ${ACTIVATED[@]+"${ACTIVATED[@]}"}

STAMP="$(date -u +%Y-%m-%d_%H-%M-%S)"
DEST="archive/${STAMP}"

echo "  → moves to ${_C_GREEN}${DEST}/${_C_RESET}  (gitignored; restore with: cp -r ${DEST}/. .)"
echo ""

# ── The data note ─────────────────────────────────────────────────────────────

echo "  ${_C_BOLD}Nothing in volumes/ is archived.${_C_RESET} Reset only moves the files above."
echo "  What happens to your volumes is decided by each name's suffix:"
echo ""

# The suffix vocabulary is enforced by `validate conventions`, so it can be
# trusted here: _cache is regenerable, everything else is not.
_vol_size() {
    local total=0 d sz
    for d in "$@"; do
        # du fails on a directory the container locked down (nextcloud's data dir
        # is 0770 www-data). Missing size must read as 0, never as empty — an
        # empty string turns the arithmetic below into a syntax error.
        sz="$(du -sm "$d" 2>/dev/null | cut -f1)"
        sz="${sz//[!0-9]/}"
        total=$(( total + ${sz:-0} ))
    done
    # Integer maths only — bc is not in the adhoc image.
    if [[ "$total" -ge 1024 ]]; then printf '%d.%dG' "$(( total / 1024 ))" "$(( (total % 1024) * 10 / 1024 ))"; else printf '%dM' "$total"; fi
}
_CACHES=(); _KEEPS=()
if [[ -d "${REPO_DIR}/volumes" ]]; then
    for d in "${REPO_DIR}"/volumes/*/; do
        [[ -d "$d" ]] || continue
        case "$(basename "$d")" in
            *_cache) _CACHES+=("$d") ;;
            *)       _KEEPS+=("$d")  ;;
        esac
    done
fi
[[ ${#_KEEPS[@]}  -gt 0 ]] && echo "    ${#_KEEPS[@]} × *_data / *_backup   $(_vol_size "${_KEEPS[@]}")  files, databases, archives — never deleted here"
[[ ${#_CACHES[@]} -gt 0 ]] && echo "    ${#_CACHES[@]} × *_cache             $(_vol_size "${_CACHES[@]}")  models and caches — regenerable, offered below"
echo ""

# Caches are the one category it is always safe to offer: by definition the
# stack rebuilds them. Everything else stays the user's job, with the stack down.
if [[ ${#_CACHES[@]} -gt 0 ]]; then
    read -rp "  Also delete the ${#_CACHES[@]} *_cache volume(s)? [y/N] " _nuke
    if [[ "${_nuke,,}" == "y" || "${_nuke,,}" == "yes" ]]; then
        for d in "${_CACHES[@]}"; do
            rm -rf "$d" 2>/dev/null \
                && echo "  ${_C_GREEN}✓${_C_RESET}  deleted $(basename "$d")" \
                || echo "  ${_C_YELLOW}could not delete${_C_RESET} $(basename "$d") — root-owned files inside it; run ./existential.sh run fix-permissions, then reset again"
        done
        echo ""
    fi
fi

echo "  To start over completely, delete the *_data volumes yourself with the"
echo "  stack down. Nothing here will do that for you."
echo ""

# ── The warning that actually matters ─────────────────────────────────────────

if [[ -e "${REPO_DIR}/.env.shared" ]] || compgen -G "${REPO_DIR}/*/*/.env" >/dev/null 2>&1; then
    echo "  ${_C_YELLOW}⚠  Secrets are in the files above and will be regenerated.${_C_RESET}"
    echo "     If you keep the volumes, databases initialised with the OLD passwords"
    echo "     will reject the new ones. Either archive the secrets and wipe the data"
    echo "     directories too, or restore .env files from the archive afterwards."
    echo ""
fi

# An archive/ this user cannot write to fails on the very first mkdir below, and
# an unguarded mkdir under `set -e` aborts mid-move — some files archived, some
# not, and no summary saying which. Docker creates a missing bind-mount source as
# root; a root-owned archive/ is the same class of problem. Check before asking.
if [[ -e "${REPO_DIR}/archive" && ! -w "${REPO_DIR}/archive" ]]; then
    echo "  ${_C_YELLOW}⚠  archive/ is not writable by this user.${_C_RESET}" >&2
    echo "     Nothing has been moved. Reclaim it first:" >&2
    echo "       ./existential.sh run fix-permissions" >&2
    echo "" >&2
    exit 1
fi

read -rp "  Archive ${TOTAL} file(s)? [y/N] " _confirm
if [[ "${_confirm,,}" != "y" && "${_confirm,,}" != "yes" ]]; then
    echo ""
    echo "  Nothing changed."
    echo ""
    exit 0
fi

# ── Move ──────────────────────────────────────────────────────────────────────

_moved=0
_failed=0
for rel in ${RENDERED[@]+"${RENDERED[@]}"} ${GENERATED[@]+"${GENERATED[@]}"} ${ACTIVATED[@]+"${ACTIVATED[@]}"}; do
    src="${REPO_DIR}/${rel}"
    [[ -e "$src" ]] || continue
    dst="${REPO_DIR}/${DEST}/${rel}"
    # Both halves guarded, for the same reason: one unwritable path must cost one
    # file, never the rest of the run.
    if mkdir -p "$(dirname "$dst")" 2>/dev/null && mv "$src" "$dst" 2>/dev/null; then
        _moved=$(( _moved + 1 ))
    else
        echo "  ${_C_YELLOW}could not move${_C_RESET} ${rel}" >&2
        _failed=$(( _failed + 1 ))
    fi
done

echo ""
echo "  ${_C_GREEN}✓${_C_RESET}  Archived ${_moved} file(s) to ${DEST}/"
if [[ "$_failed" -gt 0 ]]; then
    echo "  ${_C_YELLOW}${_failed} could not be moved${_C_RESET} — usually a path owned by another"
    echo "  user. Reclaim them with:  ./existential.sh run fix-permissions"
fi
echo ""
echo "  Next:  ./existential.sh        (renders everything fresh)"
echo "         docker compose up -d"
echo ""
