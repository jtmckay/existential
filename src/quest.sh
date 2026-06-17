#!/usr/bin/env bash
# quest.sh — Service enablement + quest onboarding flow.
# Invoked by: ./existential.sh quest  (or auto-launched when no services are enabled)

set -euo pipefail

if [[ -n "${IN_CONTAINER:-}" ]]; then
    REPO_DIR="/repo"
else
    REPO_DIR="${REPO_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
fi
EXIST_ENV="${REPO_DIR}/.env.shared"
EXIST_ENV_TMPL="${REPO_DIR}/.env.exist.shared"
QUESTS_DIR="${REPO_DIR}/src/quests"

hr()  { printf '%0.s─' {1..56}; echo; }
die() { echo "Error: $*" >&2; exit 1; }

_C_GREEN=$'\033[32m'
_C_YELLOW=$'\033[33m'
_C_CYAN=$'\033[36m'
_C_BOLD=$'\033[1m'
_C_RESET=$'\033[0m'

env_get() { grep -E "^${1}=" "$EXIST_ENV" 2>/dev/null | head -1 | cut -d= -f2-; }
env_set() {
    local key="$1" value="$2"
    if grep -qE "^${key}=" "$EXIST_ENV" 2>/dev/null; then
        sed -i "s|^${key}=.*|${key}=${value}|" "$EXIST_ENV"
    else
        echo "${key}=${value}" >> "$EXIST_ENV"
    fi
}

[ -f "$EXIST_ENV" ]      || die "${EXIST_ENV} not found — run ./existential.sh first"
[ -f "$EXIST_ENV_TMPL" ] || die "${EXIST_ENV_TMPL} not found"
command -v fzf >/dev/null 2>&1 || die "fzf not found"
command -v yq  >/dev/null 2>&1 || die "yq not found"

# ── Service helpers ───────────────────────────────────────────────────────────

# EXIST_IS_AI_OPEN_WEBUI → ai/open-webui
var_to_path() {
    local v="${1#EXIST_IS_}"
    local cat="${v%%_*}"
    local slug="${v#*_}"
    echo "${cat,,}/${slug,,}" | tr '_' '-'
}

# ai/open-webui → EXIST_IS_AI_OPEN_WEBUI
path_to_var() {
    local cat="${1%%/*}" slug="${1#*/}"
    echo "EXIST_IS_${cat^^}_${slug^^}" | tr '-' '_'
}

# open-webui → Open WebUI
slug_to_name() {
    case "$1" in
        open-webui)     echo "Open WebUI" ;;
        lightrag)       echo "LightRAG" ;;
        nocodb)         echo "NocoDB" ;;
        homeassistant)  echo "Home Assistant" ;;
        actual-budget)  echo "Actual Budget" ;;
        it-tools)       echo "IT Tools" ;;
        uptime-kuma)    echo "Uptime Kuma" ;;
        mcp)            echo "MCP" ;;
        *)
            echo "$1" | sed 's/-/ /g' | \
                awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) tolower(substr($i,2)); print}'
            ;;
    esac
}

declare -a _HOME_SVCS=(actual-budget homeassistant immich mealie vikunja)

# ai/ollama → "ai", services/mealie → "home", services/dashy → "misc", etc.
service_group() {
    local cat="${1%%/*}" slug="${1#*/}"
    case "$cat" in
        ai)      echo "ai" ;;
        hosting) echo "hosting" ;;
        nas)     echo "nas" ;;
        services)
            for _h in "${_HOME_SVCS[@]}"; do
                [[ "$slug" == "$_h" ]] && { echo "home"; return; }
            done
            echo "misc"
            ;;
        *)       echo "misc" ;;
    esac
}

# Discover all services from .env.exist.shared — skips entries without a compose file
discover_services() {
    while IFS='=' read -r _k _v || [[ -n "$_k" ]]; do
        _k="${_k%%#*}"   # strip inline comments
        _k="${_k// /}"   # trim spaces
        [[ "$_k" =~ ^EXIST_IS_ ]] || continue
        local _p; _p="$(var_to_path "$_k")"
        [ -f "${REPO_DIR}/${_p}/docker-compose.exist.yml" ] || continue
        echo "$_p"
    done < "$EXIST_ENV_TMPL"
}

# ── Quest helpers ─────────────────────────────────────────────────────────────

# Return 0 if all required services for a quest are enabled
quest_ready() {
    local _f="$1"
    mapfile -t _qvars < <(yq '.services[].var' "$_f" 2>/dev/null | grep -v '^null$' || true)
    for _v in "${_qvars[@]}"; do
        [[ -z "$_v" ]] && continue
        [[ "$(env_get "$_v")" == "true" ]] || return 1
    done
    return 0
}

# Print human labels of missing services for a quest (one per line)
quest_missing_labels() {
    local _f="$1"
    mapfile -t _vars   < <(yq '.services[].var'   "$_f" 2>/dev/null | grep -v '^null$' || true)
    mapfile -t _labels < <(yq '.services[].label' "$_f" 2>/dev/null | grep -v '^null$' || true)
    for _i in "${!_vars[@]}"; do
        [[ -z "${_vars[$_i]:-}" ]] && continue
        [[ "$(env_get "${_vars[$_i]}")" == "true" ]] && continue
        echo "${_labels[$_i]:-${_vars[$_i]}}"
    done
}

will_be_active() { [[ "$(env_get "$1")" == "true" ]]; }

# Offer to activate the cron-template copies declared by a single quest file.
process_quest_crons() {
    local _f="$1"
    local -a _labels=() _srcs=() _dsts=() _restarts=()
    local -a _q_srcs _q_dsts _q_labels _q_requires
    mapfile -t _q_srcs     < <(yq '.copies[].src      // ""' "$_f" 2>/dev/null || true)
    mapfile -t _q_dsts     < <(yq '.copies[].dst      // ""' "$_f" 2>/dev/null || true)
    mapfile -t _q_labels   < <(yq '.copies[].label    // ""' "$_f" 2>/dev/null || true)
    mapfile -t _q_requires < <(yq '.copies[].requires // ""' "$_f" 2>/dev/null || true)
    local _i _src _dst _req _fname _dst_abs _svc_part _restart_slug _restart_ctr _lbl
    for _i in "${!_q_srcs[@]}"; do
        _src="${_q_srcs[$_i]}"; _dst="${_q_dsts[$_i]}"
        [[ -z "$_src" || "$_src" == "null" ]] && continue
        _req="${_q_requires[$_i]:-}"
        if [[ -n "$_req" && "$_req" != "null" ]]; then
            will_be_active "$_req" || continue
        fi
        _fname="${_src##*/}"
        _dst_abs="${REPO_DIR}/${_dst%/}/"
        [ -f "${_dst_abs}${_fname}" ] && continue
        _svc_part="${_dst%%/decree/*}"
        _restart_slug="${_svc_part##*/}"
        [[ "$_restart_slug" == "decree" ]] && _restart_ctr="decree" || _restart_ctr="${_restart_slug}-decree"
        _lbl="${_q_labels[$_i]:-}"
        [[ -z "$_lbl" || "$_lbl" == "null" ]] && _lbl="$_fname"
        _labels+=("$_lbl"); _srcs+=("${REPO_DIR}/${_src}"); _dsts+=("$_dst_abs"); _restarts+=("$_restart_ctr")
    done

    [ "${#_labels[@]}" -gt 0 ] || return 0

    echo "  ── Cron templates ─────────────────────────────────────────────"
    echo ""
    local _selected_lines
    _selected_lines=$(
        for _i in "${!_labels[@]}"; do
            printf '%d\t%s\n' "$_i" "${_labels[$_i]}"
        done | fzf --multi \
                   --delimiter=$'\t' \
                   --with-nth=2 \
                   --layout=reverse \
                   --header="  Activate cron jobs for this quest — all pre-selected, deselect to skip
  ↑↓ navigate   Space toggle   Enter confirm" \
                   --prompt="Activate ❯ " \
                   --no-info \
                   --bind 'start:select-all' \
                   --bind 'space:toggle+down'
    ) || _selected_lines=""

    [[ -n "$_selected_lines" ]] || { echo "  (skipped)"; echo ""; return 0; }

    echo ""
    local -A _restart_needed=()
    local _line _idx2 _rel_src _rel_dst
    while IFS= read -r _line; do
        [[ -z "$_line" ]] && continue
        _idx2="${_line%%	*}"
        _src="${_srcs[$_idx2]}"; _dst="${_dsts[$_idx2]}"
        _fname="${_src##*/}"
        _rel_src="${_src#"${REPO_DIR}/"}"
        _rel_dst="${_dst#"${REPO_DIR}/"}"
        mkdir -p "$_dst"
        if cp -n "$_src" "${_dst}${_fname}" 2>/dev/null; then
            echo "  ✓ cp ${_rel_src}  →  ${_rel_dst}"
            _restart_needed["${_restarts[$_idx2]}"]=1
        else
            echo "  ↷ ${_fname} — already exists, skipped"
        fi
    done <<< "$_selected_lines"

    if [ "${#_restart_needed[@]}" -gt 0 ]; then
        echo ""
        echo "  Restart to activate:"
        local _svc
        for _svc in "${!_restart_needed[@]}"; do
            echo "    docker compose restart ${_svc}"
        done
    fi
    echo ""
}

# ── DNS tip ───────────────────────────────────────────────────────────────────

echo ""
hr
echo "  Getting started — accessing your services"
hr
echo ""
echo "  Every service runs at https://<slug>.<domain> (EXIST_DOMAIN, default x.internal)."
echo "  You need DNS to reach them from a browser."
echo ""
echo "  Option A  Enable Pihole (Hosting group) and point your router's"
echo "            upstream DNS at this machine's IP. Every device on your"
echo "            network will resolve *.<domain> automatically."
echo ""
echo "  Option B  No Pihole — wildcard record on this machine only:"
echo "              dnsmasq:  address=/<domain>/<this-machine-ip>"
echo ""

# ── Phase 1: Service picker ───────────────────────────────────────────────────

declare -a _all_svcs=()
while IFS= read -r _s; do _all_svcs+=("$_s"); done < <(discover_services)

_GOTO="__GOTO_QUESTS__"

_svc_fzf_out=$(
    {
        printf '%s\t%s▶  Go to quests%s  — choose automations and integrations to set up\n' \
            "$_GOTO" "$_C_CYAN" "$_C_RESET"

        for _grp in ai hosting nas home misc; do
            _grp_svcs=()
            for _svc in "${_all_svcs[@]}"; do
                [[ "$(service_group "$_svc")" == "$_grp" ]] && _grp_svcs+=("$_svc") || true
            done
            [ "${#_grp_svcs[@]}" -eq 0 ] && continue

            case "$_grp" in
                ai)      _hdr="── AI ────────────────────────────────────────────────────" ;;
                hosting) _hdr="── Hosting ───────────────────────────────────────────────" ;;
                nas)     _hdr="── NAS ───────────────────────────────────────────────────" ;;
                home)    _hdr="── Home ──────────────────────────────────────────────────" ;;
                misc)    _hdr="── Misc ──────────────────────────────────────────────────" ;;
            esac
            printf '__HEADER_%s__\t%s%s%s\n' "${_grp^^}" "$_C_BOLD" "$_hdr" "$_C_RESET"

            for _svc in "${_grp_svcs[@]}"; do
                _var="$(path_to_var "$_svc")"
                _name="$(slug_to_name "${_svc#*/}")"
                if [[ "$(env_get "$_var")" == "true" ]]; then
                    printf '%s\t  %s✓%s  %s\n' "$_svc" "$_C_GREEN" "$_C_RESET" "$_name"
                else
                    printf '%s\t     %s\n' "$_svc" "$_name"
                fi
            done
        done
    } | fzf --multi \
            --ansi \
            --delimiter=$'\t' \
            --with-nth=2 \
            --layout=reverse \
            --header="  Which services do you want to run?
  ↑↓ navigate   Space toggle   Enter confirm
  ${_C_GREEN}✓${_C_RESET} = already enabled   Selecting a group header enables all in that group" \
            --prompt="Services ❯ " \
            --no-info \
            --bind 'space:toggle+down'
) || { echo "Nothing selected."; exit 0; }
[[ -z "$_svc_fzf_out" ]] && { echo "Nothing selected."; exit 0; }

# Parse selection: detect "Go to quests", headers, and individual services
_goto_selected=0
echo "$_svc_fzf_out" | grep -qF "$_GOTO" && _goto_selected=1 || true

declare -A _hdr_selected=()
declare -a _explicit_svcs=()

while IFS= read -r _line; do
    [[ -z "$_line" ]] && continue
    _key="${_line%%	*}"
    case "$_key" in
        "$_GOTO") ;;
        __HEADER_AI__)      _hdr_selected[ai]=1 ;;
        __HEADER_HOSTING__) _hdr_selected[hosting]=1 ;;
        __HEADER_NAS__)     _hdr_selected[nas]=1 ;;
        __HEADER_HOME__)    _hdr_selected[home]=1 ;;
        __HEADER_MISC__)    _hdr_selected[misc]=1 ;;
        *)                  _explicit_svcs+=("$_key") ;;
    esac
done <<< "$_svc_fzf_out"

# Count explicit service selections per group (used to decide header expansion)
declare -A _grp_explicit_count=()
for _svc in "${_explicit_svcs[@]}"; do
    _g="$(service_group "$_svc")"
    _grp_explicit_count[$_g]=$(( ${_grp_explicit_count[$_g]:-0} + 1 ))
done

# Final enable set: individual services + header expansions
# Header expansion rule: if header selected with no explicit children → add all in group;
# if explicit children also selected → use only those (user made fine-grained choice).
declare -A _enable_set=()
for _svc in "${_explicit_svcs[@]}"; do _enable_set[$_svc]=1; done

for _grp in "${!_hdr_selected[@]}"; do
    if [[ "${_grp_explicit_count[$_grp]:-0}" -eq 0 ]]; then
        for _svc in "${_all_svcs[@]}"; do
            [[ "$(service_group "$_svc")" == "$_grp" ]] && _enable_set[$_svc]=1 || true
        done
    fi
done

# Write enabled services to .env.shared
_newly_enabled=0
declare -a _newly_enabled_svcs=()
for _svc in "${!_enable_set[@]}"; do
    _var="$(path_to_var "$_svc")"
    if [[ "$(env_get "$_var")" != "true" ]]; then
        env_set "$_var" "true"
        _newly_enabled=$(( _newly_enabled + 1 ))
        _newly_enabled_svcs+=("$_svc")
    fi
done

if [[ "$_newly_enabled" -gt 0 ]]; then
    echo ""
    echo "  Enabled ${_newly_enabled} new service(s) in ${EXIST_ENV}."
fi

# Only enter quest screen if "Go to quests" was selected or nothing was selected
if [[ "$_goto_selected" -eq 0 && "${#_enable_set[@]}" -gt 0 ]]; then
    exit 0
fi

# ── Phase 2: Quest picker ─────────────────────────────────────────────────────

echo ""

declare -a _quest_files=()
while IFS= read -r f; do _quest_files+=("$f"); done < <(find "$QUESTS_DIR" -name '*.yml' -type f | sort)
[ "${#_quest_files[@]}" -gt 0 ] || die "No quest files found in ${QUESTS_DIR}"

_quest_fzf_out=$(
    {
        for _f in "${_quest_files[@]}"; do
            if quest_ready "$_f"; then _qdot="${_C_GREEN}●${_C_RESET}"; else _qdot="${_C_YELLOW}●${_C_RESET}"; fi
            printf '%s\t%s  (%s) %-24s  %s\n' \
                "$_f" "$_qdot" "$(yq '.services | length' "$_f")" \
                "$(yq '.name' "$_f")" "$(yq '.tagline' "$_f")"
        done
    } | fzf --multi \
            --ansi \
            --delimiter=$'\t' \
            --with-nth=2 \
            --layout=reverse \
            --header="  Pick quests — what do you want to set up?
  ↑↓ navigate   Space toggle   Enter confirm
  ${_C_GREEN}●${_C_RESET} = services ready   ${_C_YELLOW}●${_C_RESET} = some services not yet enabled
  Hit Enter with nothing selected to run the highlighted quest" \
            --prompt="Quest ❯ " \
            --no-info \
            --bind 'space:toggle+down'
) || { echo "Nothing selected."; exit 0; }
[[ -z "$_quest_fzf_out" ]] && { echo "Nothing selected."; exit 0; }

declare -a _active_files=()
declare -A _file_seen=()
while IFS= read -r _line; do
    [[ -z "$_line" ]] && continue
    _f="${_line%%	*}"
    [[ "${_file_seen[$_f]:-}" == "1" ]] && continue
    _file_seen[$_f]=1
    _active_files+=("$_f")
done <<< "$_quest_fzf_out"

[ "${#_active_files[@]}" -gt 0 ] || { echo "Nothing selected."; exit 0; }

# ── Enable missing services for selected quests ───────────────────────────────

declare -A _quest_missing_vars=()
declare -A _quest_missing_labels=()
for _f in "${_active_files[@]}"; do
    mapfile -t _qsvars   < <(yq '.services[].var   // ""' "$_f" 2>/dev/null | grep -v '^null$\|^$' || true)
    mapfile -t _qslabels < <(yq '.services[].label // ""' "$_f" 2>/dev/null | grep -v '^null$\|^$' || true)
    for _i in "${!_qsvars[@]}"; do
        _v="${_qsvars[$_i]:-}"
        [[ -z "$_v" || "$_v" == "null" ]] && continue
        [[ "$(env_get "$_v")" == "true" ]] && continue
        _quest_missing_vars["$_v"]=1
        _quest_missing_labels["$_v"]="${_qslabels[$_i]:-$_v}"
    done
done

if [[ "${#_quest_missing_vars[@]}" -gt 0 ]]; then
    echo ""
    _svc_enable_out=$(
        {
            for _v in $(printf '%s\n' "${!_quest_missing_vars[@]}" | sort); do
                printf '%s\t  %s\n' "$_v" "${_quest_missing_labels[$_v]}"
            done
        } | fzf --multi \
                --ansi \
                --delimiter=$'\t' \
                --with-nth=2 \
                --layout=reverse \
                --header="  These services are needed by your selected quests — all pre-selected, deselect to skip
  ↑↓ navigate   Space toggle   Enter confirm" \
                --prompt="Enable ❯ " \
                --no-info \
                --bind 'start:select-all' \
                --bind 'space:toggle+down'
    ) || _svc_enable_out=""

    _new_count=0
    if [[ -n "$_svc_enable_out" ]]; then
        while IFS= read -r _line; do
            [[ -z "$_line" ]] && continue
            _v="${_line%%	*}"
            [[ "$(env_get "$_v")" == "true" ]] && continue
            env_set "$_v" "true"
            _newly_enabled=$(( _newly_enabled + 1 ))
            _new_count=$(( _new_count + 1 ))
            _newly_enabled_svcs+=("$(var_to_path "$_v")")
        done <<< "$_svc_enable_out"
        [[ "$_new_count" -gt 0 ]] && echo "  Enabled ${_new_count} new service(s) in ${EXIST_ENV}."
    fi
fi

# ── Global setup notes (shown once) ───────────────────────────────────────────

echo ""
hr
echo "  Setup guide"
hr
echo ""
echo "  ── What ./existential.sh handles automatically ──────────────"
echo ""
echo "  Renders config templates for all newly-enabled services."

_auto_initials=()
for _svc in "${_newly_enabled_svcs[@]}"; do
    [ -f "${REPO_DIR}/${_svc}/exist.initial.sh" ] || continue
    _auto_initials+=("${_svc##*/}")
done
if [ "${#_auto_initials[@]}" -gt 0 ]; then
    echo "  Runs interactive first-time setup for:"
    for _s in "${_auto_initials[@]}"; do
        echo "    ./existential.sh run ${_s}   (re-run anytime to reconfigure)"
    done
fi
echo ""

_has_decree=0; will_be_active EXIST_IS_SERVICES_DECREE        && _has_decree=1 || true
_has_budget=0; will_be_active EXIST_IS_SERVICES_ACTUAL_BUDGET && _has_budget=1 || true
_has_pihole=0; will_be_active EXIST_IS_HOSTING_PIHOLE         && _has_pihole=1 || true
_has_caddy=0;  will_be_active EXIST_IS_HOSTING_CADDY          && _has_caddy=1  || true

_run_steps=()
if [[ "$_has_decree" -eq 1 ]]; then
    _run_steps+=("── Decree integrations (run after decree starts) ──────────────────")
    _run_steps+=("  ./existential.sh run decree gmail-sync")
    _run_steps+=("    Connect a Gmail account so Decree can read and route emails.")
    _run_steps+=("  ./existential.sh run decree gmail-labels")
    _run_steps+=("    Sync your Gmail label list — re-run after adding or renaming labels.")
    if [[ "$_has_budget" -eq 1 ]]; then
        _run_steps+=("  ./existential.sh run decree gmail-transactions-cron")
        _run_steps+=("    Wire Gmail receipt parsing → Actual Budget import.")
    fi
    _run_steps+=("")
fi

if [ "${#_run_steps[@]}" -gt 0 ]; then
    echo "  ── Optional integrations (run after services start) ──────────"
    echo ""
    for _line in "${_run_steps[@]}"; do echo "  ${_line}"; done
fi

# ── Per-quest walkthrough — one quest at a time ────────────────────────────────

_total="${#_active_files[@]}"
_qi=0
for _f in "${_active_files[@]}"; do
    _qi=$(( _qi + 1 ))
    _qname="$(yq '.name' "$_f")"

    echo ""
    hr
    echo "  Quest ${_qi}/${_total} — ${_qname}"
    hr
    echo ""

    # Missing services this quest needs
    _miss=()
    while IFS= read -r _lbl; do
        [[ -n "$_lbl" ]] && _miss+=("$_lbl")
    done < <(quest_missing_labels "$_f" || true)
    if [ "${#_miss[@]}" -gt 0 ]; then
        echo "  ⚠  This quest needs services that aren't enabled yet:"
        for _m in "${_miss[@]}"; do echo "       • ${_m}"; done
        echo ""
        echo "  Enable them via ./existential.sh quest, then run ./existential.sh"
        echo "  to apply. The guide below still applies."
        echo ""
    fi

    # Quest guide
    _guide=$(yq '.guide // ""' "$_f")
    if [[ -n "$_guide" && "$_guide" != "null" ]]; then
        echo "$_guide" | sed 's/^/  /'
        echo ""
    fi

    # Cron templates for this quest
    process_quest_crons "$_f"

    # Prompt before moving on, unless this was the last quest
    if [ "$_qi" -lt "$_total" ]; then
        read -rp "  Press Enter for the next quest (Ctrl-C to stop)… " _
    fi
done

if [[ "$_has_pihole" -eq 1 || "$_has_caddy" -eq 1 ]]; then
    echo ""
    hr
    echo "  Accessing services"
    hr
    echo ""
    echo "  Each enabled service is reachable at https://<slug>.<domain> (EXIST_DOMAIN)."
    echo ""
    if [[ "$_has_pihole" -eq 1 ]]; then
        echo "  Pihole handles DNS — point your router at it so slugs resolve:"
        echo "    ./existential.sh run pihole"
        echo ""
    fi
    if [[ "$_has_caddy" -eq 1 ]]; then
        echo "  Caddy handles TLS with a local CA. Install its root cert once"
        echo "  per device for green padlocks:"
        echo "    https://caddy.<domain>/caddy-root.crt  (after first run)"
        echo ""
    fi
fi

# ── Remaining cron templates (informational) ──────────────────────────────────

_remaining=()
while IFS='=' read -r _k _v || [[ -n "$_k" ]]; do
    [[ "$_k" =~ ^EXIST_IS_ ]] && [[ "$_v" == "true" ]] || continue
    _svc_path="$(var_to_path "$_k")"
    _cron_ex="${REPO_DIR}/${_svc_path}/decree/cron.example"
    [ -d "$_cron_ex" ] || continue
    _dst_dir="${REPO_DIR}/${_svc_path}/decree/cron/"
    while IFS= read -r _cf; do
        _fname="${_cf##*/}"
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
    for _r in "${_remaining[@]}"; do echo "  ${_r}"; done
    echo ""
    echo "  Re-run ./existential.sh quest to activate interactively."
    echo ""
fi
