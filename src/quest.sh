#!/usr/bin/env bash
# Quest picker + onboarding guide.
# Reads quest definitions from src/quests/*.yml via yq.
# Invoked by: ./existential.sh quest

set -euo pipefail

if [[ -n "${IN_CONTAINER:-}" ]]; then
    REPO_DIR="/repo"
else
    REPO_DIR="${REPO_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
fi
EXIST_ENV="${REPO_DIR}/.env.shared"
QUESTS_DIR="${REPO_DIR}/src/quests"

hr()  { printf '%0.s─' {1..56}; echo; }
die() { echo "Error: $*" >&2; exit 1; }

env_get() { grep -E "^${1}=" "$EXIST_ENV" 2>/dev/null | head -1 | cut -d= -f2-; }
env_set() {
    local key="$1" value="$2"
    if grep -qE "^${key}=" "$EXIST_ENV" 2>/dev/null; then
        sed -i "s|^${key}=.*|${key}=${value}|" "$EXIST_ENV"
    else
        echo "${key}=${value}" >> "$EXIST_ENV"
    fi
}

[ -f "$EXIST_ENV" ] || die "${EXIST_ENV} not found — run ./existential.sh first"

# Derive filesystem path from EXIST_IS_* variable name.
# EXIST_IS_AI_OPEN_WEBUI → ai/open-webui
var_to_path() {
    local v="${1#EXIST_IS_}"
    local cat="${v%%_*}"
    local slug="${v#*_}"
    echo "${cat,,}/${slug,,}" | tr '_' '-'
}

# ── Phase 1: Quest selection ───────────────────────────────────────────────────

declare -a _quest_files=()
while IFS= read -r f; do _quest_files+=("$f"); done < <(find "$QUESTS_DIR" -name '*.yml' -type f | sort)
[ "${#_quest_files[@]}" -gt 0 ] || die "No quest files found in ${QUESTS_DIR}"

_fzf_out=$(
    for _f in "${_quest_files[@]}"; do
        _e2e=$(yq '.e2e // "null"' "$_f" | tr -d '"')
        case "$_e2e" in
            true)  _badge="  \033[32m● auto\033[0m"   ;;
            false) _badge="  \033[33m○ manual\033[0m" ;;
            *)     _badge=""                            ;;
        esac
        printf '%s\t%-32s  %s%b\n' "$_f" "$(yq '.name' "$_f")" "$(yq '.tagline' "$_f")" "$_badge"
    done | fzf --multi \
               --ansi \
               --delimiter=$'\t' \
               --with-nth=2 \
               --layout=reverse \
               --header="  Pick quests — what do you want to build?
  ↑↓ navigate   Space toggle   Enter confirm
  \033[32m● auto\033[0m = fully automatable   \033[33m○ manual\033[0m = requires setup steps" \
               --prompt="Quest ❯ " \
               --no-info \
               --bind 'space:toggle+down'
) || { echo "Nothing selected."; exit 0; }
[[ -z "$_fzf_out" ]] && { echo "Nothing selected."; exit 0; }

declare -a _active_files=()
declare -A _file_seen=()
while IFS= read -r _line; do
    [[ -z "$_line" ]] && continue
    _f="${_line%%	*}"
    [[ "${_file_seen[$_f]:-}" == "1" ]] && continue
    _file_seen[$_f]=1
    _active_files+=("$_f")
done <<< "$_fzf_out"

# ── Phase 2: Build service checklist ──────────────────────────────────────────

declare -a CL_VARS=()
declare -A CL_SEEN=()
declare -A CL_LABELS=()
declare -A CL_ENABLED=()
declare -A CL_SELECTED=()

for _f in "${_active_files[@]}"; do
    mapfile -t _vars   < <(yq '.services[].var'   "$_f" 2>/dev/null || true)
    mapfile -t _labels < <(yq '.services[].label' "$_f" 2>/dev/null || true)
    for _i in "${!_vars[@]}"; do
        _var="${_vars[$_i]}"
        [[ -z "$_var" || "$_var" == "null" ]] && continue
        [[ "${CL_SEEN[$_var]:-}" == "1" ]] && continue
        CL_SEEN[$_var]=1
        CL_VARS+=("$_var")
        CL_LABELS[$_var]="${_labels[$_i]}"
        [[ "$(env_get "$_var")" == "true" ]] && CL_ENABLED[$_var]=1 || true
        CL_SELECTED[$_var]=1
    done
done

_guide_only=0
[ "${#CL_VARS[@]}" -gt 0 ] || _guide_only=1

if [ "$_guide_only" -eq 1 ]; then
    echo ""
    echo "  This quest has no service flags — skipping to guide."
fi

_quest_title() {
    local titles=()
    for _f in "${_active_files[@]}"; do titles+=("$(yq '.name' "$_f")"); done
    ( IFS=' + '; echo "${titles[*]}" )
}

declare -a NEW_VARS=()

if [ "$_guide_only" -eq 0 ]; then
    _fzf_vars=()
    _fzf_labels=()
    _already_labels=()
    for _var in "${CL_VARS[@]}"; do
        if [[ "${CL_ENABLED[$_var]:-}" == "1" ]]; then
            _already_labels+=("${CL_LABELS[$_var]}")
        else
            _fzf_vars+=("$_var")
            _fzf_labels+=("${CL_LABELS[$_var]}")
        fi
    done

    echo ""
    hr
    printf "  %s\n" "$(_quest_title)"
    hr
    echo ""
    if [ "${#_already_labels[@]}" -gt 0 ]; then
        echo "  Already enabled (kept): $(IFS=', '; echo "${_already_labels[*]}")"
        echo ""
    fi

    if [ "${#_fzf_vars[@]}" -gt 0 ]; then
        _fzf_selected=$(
            printf '%s\n' "${_fzf_labels[@]}" | fzf --multi \
                --layout=reverse \
                --header="  Recommended services (all pre-selected — deselect to skip)
  ↑↓ navigate   Space toggle   Enter confirm" \
                --prompt="Service ❯ " \
                --no-info \
                --bind 'start:select-all' \
                --bind 'space:toggle+down'
        ) || { echo "  Aborted."; exit 0; }

        for _var in "${CL_VARS[@]}"; do CL_SELECTED[$_var]=0; done
        for _var in "${CL_VARS[@]}"; do
            [[ "${CL_ENABLED[$_var]:-}" == "1" ]] && CL_SELECTED[$_var]=1
        done
        while IFS= read -r _lbl; do
            [[ -z "$_lbl" ]] && continue
            for _i in "${!_fzf_labels[@]}"; do
                if [[ "${_fzf_labels[$_i]}" == "$_lbl" ]]; then
                    CL_SELECTED[${_fzf_vars[$_i]}]=1
                    break
                fi
            done
        done <<< "$_fzf_selected"
    fi

    for _var in "${CL_VARS[@]}"; do
        if [[ "${CL_ENABLED[$_var]:-}" != "1" && "${CL_SELECTED[$_var]:-}" == "1" ]]; then
            NEW_VARS+=("$_var")
        fi
    done

    if [ "${#NEW_VARS[@]}" -eq 0 ]; then
        echo "  All selected services are already enabled. Nothing to do."
        exit 0
    fi
fi

# ── Collect copy candidates ────────────────────────────────────────────────────
# Explicit entries from each quest's `copies:` field.
# `requires:` guards against showing copies for services the user didn't select.
# Deduped by src path so overlapping quests don't double-list the same file.

will_be_active() {
    [[ "${CL_ENABLED[$1]:-}" == "1" || "${CL_SELECTED[$1]:-}" == "1" ]]
}

declare -a _copy_labels=()
declare -a _copy_srcs=()
declare -a _copy_dsts=()
declare -a _copy_restarts=()
declare -A _copy_src_seen=()

for _f in "${_active_files[@]}"; do
    mapfile -t _q_srcs     < <(yq '.copies[].src     // ""' "$_f" 2>/dev/null || true)
    mapfile -t _q_dsts     < <(yq '.copies[].dst     // ""' "$_f" 2>/dev/null || true)
    mapfile -t _q_labels   < <(yq '.copies[].label   // ""' "$_f" 2>/dev/null || true)
    mapfile -t _q_requires < <(yq '.copies[].requires // ""' "$_f" 2>/dev/null || true)
    for _i in "${!_q_srcs[@]}"; do
        _src="${_q_srcs[$_i]}"
        _dst="${_q_dsts[$_i]}"
        [[ -z "$_src" || "$_src" == "null" ]] && continue
        # Skip if required service is not selected/enabled
        _req="${_q_requires[$_i]:-}"
        if [[ -n "$_req" && "$_req" != "null" ]]; then
            will_be_active "$_req" || continue
        fi
        # Skip if already copied
        _fname="${_src##*/}"
        _dst_abs="${REPO_DIR}/${_dst%/}/"
        [ -f "${_dst_abs}${_fname}" ] && continue
        # Dedup by src path
        [[ "${_copy_src_seen[$_src]:-}" == "1" ]] && continue
        _copy_src_seen[$_src]=1
        # Derive container to restart from dst path (slug-decree or decree for main daemon)
        _svc_part="${_dst%%/decree/*}"
        _restart_slug="${_svc_part##*/}"
        [[ "$_restart_slug" == "decree" ]] && _restart_ctr="decree" || _restart_ctr="${_restart_slug}-decree"
        _lbl="${_q_labels[$_i]:-}"
        [[ -z "$_lbl" || "$_lbl" == "null" ]] && _lbl="$_fname"
        _copy_labels+=("$_lbl")
        _copy_srcs+=("${REPO_DIR}/${_src}")
        _copy_dsts+=("$_dst_abs")
        _copy_restarts+=("$_restart_ctr")
    done
done

# ── Phase 3: Quest guide ───────────────────────────────────────────────────────

echo ""
hr
echo "  Quest guide — $(_quest_title)"
hr

echo ""
echo "  ── What ./existential.sh handles automatically ──────────────"
echo ""
echo "  Renders config templates for all newly-enabled services."
_auto_initials=()
for _var in "${NEW_VARS[@]}"; do
    _svc_path="$(var_to_path "$_var")"
    [ -f "${REPO_DIR}/${_svc_path}/exist.initial.sh" ] || continue
    _auto_initials+=("${_svc_path##*/}")
done
if [ "${#_auto_initials[@]}" -gt 0 ]; then
    echo "  Runs interactive first-time setup for:"
    for _s in "${_auto_initials[@]}"; do
        echo "    ./existential.sh run ${_s}   (re-run anytime to reconfigure)"
    done
fi
echo ""

_has_decree=0;  will_be_active EXIST_IS_SERVICES_DECREE        && _has_decree=1  || true
_has_budget=0;  will_be_active EXIST_IS_SERVICES_ACTUAL_BUDGET && _has_budget=1  || true
_has_pihole=0;  will_be_active EXIST_IS_HOSTING_PIHOLE         && _has_pihole=1  || true
_has_caddy=0;   will_be_active EXIST_IS_HOSTING_CADDY          && _has_caddy=1   || true

_run_steps=()

if [[ "$_has_decree" -eq 1 && "${CL_ENABLED[EXIST_IS_SERVICES_DECREE]:-}" != "1" ]]; then
    _run_steps+=("── Decree integrations (run after decree starts) ─────────────────")
    _run_steps+=("  ./existential.sh run decree gmail-sync")
    _run_steps+=("    Connect a Gmail account so Decree can read and route emails.")
    _run_steps+=("  ./existential.sh run decree gmail-labels")
    _run_steps+=("    Sync your Gmail label list — re-run after adding or renaming labels.")
    if [[ "$_has_budget" -eq 1 ]]; then
        _run_steps+=("  ./existential.sh run decree gmail-transactions-cron")
        _run_steps+=("    Wire Gmail receipt parsing → Actual Budget import.")
    fi
    _run_steps+=("")
elif [[ "$_has_decree" -eq 1 && "$_has_budget" -eq 1 && "${CL_ENABLED[EXIST_IS_SERVICES_ACTUAL_BUDGET]:-}" != "1" ]]; then
    _run_steps+=("── Decree + Actual Budget ────────────────────────────────────────")
    _run_steps+=("  ./existential.sh run decree gmail-transactions-cron")
    _run_steps+=("    Wire Gmail receipt parsing → Actual Budget import.")
    _run_steps+=("")
fi

if [ "${#_run_steps[@]}" -gt 0 ]; then
    echo "  ── Optional integrations (run after services start) ──────────"
    echo ""
    for _line in "${_run_steps[@]}"; do
        echo "  ${_line}"
    done
fi

if [ "${#_copy_labels[@]}" -gt 0 ]; then
    echo "  ── Cron templates (${#_copy_labels[@]} available) ────────────────────────────────"
    echo ""
    echo "  After confirming, you'll be prompted to activate cron jobs."
    echo "  Each template's schedule is in its frontmatter — edit before"
    echo "  copying if you want a different schedule."
    echo ""
fi

# Quest-specific guide content from YAML
for _f in "${_active_files[@]}"; do
    _guide=$(yq '.guide // ""' "$_f")
    [[ -z "$_guide" ]] && continue
    echo "  ── $(yq '.name' "$_f") ─────────────────────────────────────"
    echo ""
    echo "$_guide" | sed 's/^/  /'
    echo ""
done

if [[ "$_has_pihole" -eq 1 || "$_has_caddy" -eq 1 ]]; then
    echo "  ── Accessing services ─────────────────────────────────────────"
    echo ""
    echo "  Each enabled service is reachable at https://<slug>.internal."
    echo ""
    if [[ "$_has_pihole" -eq 1 ]]; then
        echo "  Pihole handles DNS — point your router (or just this machine)"
        echo "  at it so slugs resolve. The setup script walks you through this:"
        echo "    ./existential.sh run pihole"
        echo ""
    fi
    if [[ "$_has_caddy" -eq 1 ]]; then
        echo "  Caddy handles TLS with a local CA. Install its root cert once"
        echo "  per device for green padlocks in your browser:"
        echo "    https://caddy.internal/caddy-root.crt  (after first run)"
        echo ""
        echo "  Caddy is auto-configured for every enabled service slug."
        echo "  To add a public domain or regenerate config:"
        echo "    ./existential.sh run caddy"
        echo ""
    fi
fi

# ── Phase 4 + 5: Confirm, write flags, activate copies ────────────────────────

if [ "$_guide_only" -eq 0 ]; then

    hr
    echo ""
    _labels=()
    for _var in "${NEW_VARS[@]}"; do _labels+=("${CL_LABELS[$_var]}"); done
    printf "  Enabling %d service(s): %s\n" "${#NEW_VARS[@]}" "$(IFS=', '; echo "${_labels[*]}")"
    if [ "${#_copy_labels[@]}" -gt 0 ]; then
        printf "  Activating %d cron template(s) (selectable next step)\n" "${#_copy_labels[@]}"
    fi
    echo ""
    read -rp "  Confirm and run setup? [Y/n]: " _confirm
    case "${_confirm:-y}" in
        y|Y|yes|YES) ;;
        *) echo "  Aborted."; exit 0 ;;
    esac

    echo ""
    for _var in "${NEW_VARS[@]}"; do
        env_set "$_var" "true"
    done
    echo "  Enabled ${#NEW_VARS[@]} service(s) in ${EXIST_ENV}."

    if [ "${#_copy_labels[@]}" -gt 0 ]; then
        echo ""
        hr
        echo "  Activate cron templates"
        hr
        echo ""

        _selected_lines=$(
            for _i in "${!_copy_labels[@]}"; do
                printf '%d\t%s\n' "$_i" "${_copy_labels[$_i]}"
            done | fzf --multi \
                       --delimiter=$'\t' \
                       --with-nth=2 \
                       --layout=reverse \
                       --header="  All pre-selected — deselect any to skip
  ↑↓ navigate   Space toggle   Enter confirm" \
                       --prompt="Activate ❯ " \
                       --no-info \
                       --bind 'start:select-all' \
                       --bind 'space:toggle+down'
        ) || _selected_lines=""

        if [[ -n "$_selected_lines" ]]; then
            echo ""
            declare -A _restart_needed=()
            while IFS= read -r _line; do
                [[ -z "$_line" ]] && continue
                _idx="${_line%%	*}"
                _src="${_copy_srcs[$_idx]}"
                _dst="${_copy_dsts[$_idx]}"
                _fname="${_src##*/}"
                _rel_src="${_src#"${REPO_DIR}/"}"
                _rel_dst="${_dst#"${REPO_DIR}/"}"
                mkdir -p "$_dst"
                if cp -n "$_src" "${_dst}${_fname}" 2>/dev/null; then
                    echo "  ✓ cp ${_rel_src}  →  ${_rel_dst}"
                    _restart_needed["${_copy_restarts[$_idx]}"]=1
                else
                    echo "  ↷ ${_fname} — already exists, skipped"
                fi
            done <<< "$_selected_lines"

            if [ "${#_restart_needed[@]}" -gt 0 ]; then
                echo ""
                echo "  Restart to activate:"
                for _svc in "${!_restart_needed[@]}"; do
                    echo "    docker compose restart ${_svc}"
                done
            fi
        fi
    fi

fi  # end _guide_only check

# ── Informational: remaining cron templates ────────────────────────────────────
# Scan all enabled services for cron.example files not yet copied to cron/.

_remaining=()
while IFS='=' read -r _k _v || [[ -n "$_k" ]]; do
    [[ "$_k" =~ ^EXIST_IS_ ]] && [[ "$_v" == "true" ]] || continue
    _svc_path="$(var_to_path "$_k")"
    _cron_ex="${REPO_DIR}/${_svc_path}/decree/cron.example"
    [ -d "$_cron_ex" ] || continue
    _dst_dir="${REPO_DIR}/${_svc_path}/decree/cron/"
    while IFS= read -r _f; do
        _fname="${_f##*/}"
        [ -f "${_dst_dir}${_fname}" ] && continue
        _remaining+=("${_svc_path##*/}: ${_svc_path}/decree/cron.example/${_fname}")
    done < <(find "$_cron_ex" -maxdepth 1 -name '*.md' -type f 2>/dev/null | sort)
done < "$EXIST_ENV"

if [ "${#_remaining[@]}" -gt 0 ]; then
    echo ""
    hr
    echo "  Cron templates not yet activated"
    hr
    echo ""
    for _r in "${_remaining[@]}"; do
        echo "  ${_r}"
    done
    echo ""
    echo "  Re-run ./existential.sh quest to activate interactively."
    echo ""
fi
