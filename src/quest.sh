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

# The two hardware questions. Both sourced, never run — see their headers.
# Vendor is asked first: answering "No GPU" fixes the VRAM answer at 0, so the
# VRAM question is skipped entirely rather than asked and ignored.
# shellcheck source=src/utils/gpu-vendor.sh
. "${REPO_DIR}/src/utils/gpu-vendor.sh"
# shellcheck source=src/utils/model-tiers.sh
. "${REPO_DIR}/src/utils/model-tiers.sh"

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

declare -a _HOME_SVCS=(actual-budget homeassistant immich mealie)

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

# ── Quest file format ─────────────────────────────────────────────────────────
#
# A quest is a markdown file: YAML frontmatter for the data, the body for the
# guide. Same shape as decree's cron and migration files, which is what these
# guides tell you to copy — and it keeps 60% of each file (the prose) out of a
# YAML block scalar, where indentation was load-bearing and nothing rendered it.
#
#     ---
#     name: Core
#     services:
#       - var: EXIST_IS_AI_OLLAMA
#         label: Ollama
#     ---
#
#     Everything after the closing fence is the guide.
#
# The frontmatter is ordinary YAML — nested lists and maps included. It is read
# by yq here, NOT by decree, so decree's "extra keys become env vars" contract
# does not apply.

# qmeta <file> <yq-expr> — evaluate a yq expression against the frontmatter.
qmeta() {
    awk 'NR==1 && /^---$/{f=1;next} f && /^---$/{exit} f' "$1" | yq "$2" 2>/dev/null
}

# qbody <file> — the guide: everything after the closing fence.
qbody() {
    awk 'NR==1 && /^---$/{f=1;next} f && /^---$/{f=0;b=1;next} b' "$1"
}

# ── Quest helpers ─────────────────────────────────────────────────────────────

# Return 0 if all required services for a quest are enabled
quest_ready() {
    local _f="$1"
    mapfile -t _qvars < <(qmeta "$_f" '.services[].var' 2>/dev/null | grep -v '^null$' || true)
    for _v in "${_qvars[@]}"; do
        [[ -z "$_v" ]] && continue
        [[ "$(env_get "$_v")" == "true" ]] || return 1
    done
    return 0
}

# Print human labels of missing services for a quest (one per line)
quest_missing_labels() {
    local _f="$1"
    mapfile -t _vars   < <(qmeta "$_f" '.services[].var' 2>/dev/null | grep -v '^null$' || true)
    mapfile -t _labels < <(qmeta "$_f" '.services[].label' 2>/dev/null | grep -v '^null$' || true)
    for _i in "${!_vars[@]}"; do
        [[ -z "${_vars[$_i]:-}" ]] && continue
        [[ "$(env_get "${_vars[$_i]}")" == "true" ]] && continue
        echo "${_labels[$_i]:-${_vars[$_i]}}"
    done
}

will_be_active() { [[ "$(env_get "$1")" == "true" ]]; }

# Offer to activate the cron-template copies declared by a single quest file.
# Which decree container owns a `<cat>/<slug>/decree/...` destination.
#
# Not `${dst%%/decree/*}`: services/decree/decree/cron/ has TWO "/decree/"
# segments, so that strips back to "services" and names a container
# (services-decree) that does not exist. The slug is always the second path
# component; the main daemon is plain "decree", every sidecar is "<slug>-decree".
_decree_container_for() {
    local _slug
    _slug="$(cut -d/ -f2 <<< "$1")"
    [[ "$_slug" == "decree" ]] && echo "decree" || echo "${_slug}-decree"
}

process_quest_crons() {
    local _f="$1"
    local -a _labels=() _srcs=() _dsts=()
    local _lbl _src _dst
    while IFS=$'\t' read -r _lbl _src _dst; do
        [[ -z "$_src" ]] && continue
        _labels+=("$_lbl"); _srcs+=("$_src"); _dsts+=("$_dst")
    done < <(_quest_pending_copies "$_f")

    [ "${#_labels[@]}" -gt 0 ] || return 0

    echo "  ── Templates to activate ──────────────────────────────────────"
    echo ""
    local _selected_lines
    _selected_lines=$(
        for _i in "${!_labels[@]}"; do
            printf '%d\t%s\n' "$_i" "${_labels[$_i]}"
        done | fzf --multi \
                   --delimiter=$'\t' \
                   --with-nth=2 \
                   --layout=reverse \
                   --marker='✓' \
                   --header="  All of these are ON — Enter accepts them as-is.
  Deselect one only if you do not want it (Space toggles).
  ↑↓ navigate   Space toggle   Enter confirm" \
                   --prompt="Activate ❯ " \
                   --no-info \
                   --bind 'start:select-all' \
                   --bind 'space:toggle+down'
    ) || _selected_lines=""

    [[ -n "$_selected_lines" ]] || { echo "  (skipped)"; echo ""; return 0; }

    echo ""
    local -A _restart_needed=()
    local _line _idx _fname _ctr
    while IFS= read -r _line; do
        [[ -z "$_line" ]] && continue
        _idx="${_line%%	*}"
        _src="${_srcs[$_idx]}"; _dst="${_dsts[$_idx]}"
        _fname="${_src##*/}"
        mkdir -p "${REPO_DIR}/${_dst}"
        if cp -n "${REPO_DIR}/${_src}" "${REPO_DIR}/${_dst}${_fname}" 2>/dev/null; then
            echo "  ✓ cp ${_src}  →  ${_dst}"
            _ctr="$(_decree_container_for "$_dst")"
            _restart_needed["$_ctr"]=1
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

# ── Closing suggestion: reaching it from elsewhere ────────────────────────────
#
# Nothing to decide up front. existential.sh detects the host IP — the tailnet
# address when tailscale is up — and derives a nip.io domain from it, so every
# service is reachable at https://<slug>.<domain> from every device on the
# tailnet with no DNS setup. Local-only DNS is a later, optional upgrade, so it
# belongs at the END of a run as a suggestion rather than a question at the start.
_access_tip() {
    local domain
    domain="$(env_get EXIST_DOMAIN)"
    echo ""
    hr
    echo "  Reaching your services"
    hr
    echo ""
    if [[ "$domain" == *.nip.io ]]; then
        echo "  Ready to use on this machine: ${_C_GREEN}https://<service>.${domain}${_C_RESET}"
        echo "  That name is public wildcard DNS pointing straight back at this host,"
        if [[ "$domain" == 100-* ]]; then
            echo "  which is your tailnet address — so it works from any phone or laptop"
            echo "  logged into your tailnet, anywhere, and from nowhere else. No setup."
        else
            echo "  so it works from phones and laptops on the same network too. No setup."
            echo "  ${_C_YELLOW}Tailscale is not running${_C_RESET} — start it and re-run ./existential.sh to"
            echo "  get an address that reaches your devices off this LAN too."
        fi
    elif [[ -n "$domain" ]]; then
        # A domain the user chose: .internal (needs pihole) or one they own.
        echo "  Services are served at ${_C_GREEN}https://<service>.${domain}${_C_RESET}"
        case "$domain" in
            *.internal)
                echo "  Nothing resolves .internal on its own — pihole answers it,"
                echo "  or add /etc/hosts entries on each device." ;;
        esac
    else
        echo "  Services are served at https://<service>.<EXIST_DOMAIN>."
    fi
    echo ""
    if will_be_active EXIST_IS_HOSTING_CADDY; then
        echo "  Caddy fronts them with TLS from a local CA. Install its root cert"
        echo "  once per device for a green padlock:"
        echo "    https://caddy.${domain:-<domain>}/caddy-root.crt"
    else
        echo "  ${_C_YELLOW}Caddy is not enabled${_C_RESET} — nothing is fronting those names. Enable it"
        echo "  (EXIST_IS_HOSTING_CADDY=true), or uncomment the ports: block in each"
        echo "  service's docker-compose.yml to reach them by port instead."
    fi
    echo ""
    echo "  Want more than that?"
    echo "    • Names that resolve with no internet DNS, on your own domain:"
    echo "        ./existential.sh quest  →  Network Access"
    echo "    • Real certificates, no CA to install on each device:"
    echo "        ./existential.sh run caddy public-domain"
    echo ""
}

# ── Phase 0: Core, or no thanks ───────────────────────────────────────────────
#
# On a first run the full 40-service picker is the wrong first question — it asks
# someone to make forty decisions about software they have not seen yet. Offer
# ONE decision instead: the core system, or choose for yourself.
#
# Only fires when nothing beyond the shipped defaults is enabled, so it shows up
# once and never gets in the way of `./existential.sh quest` later.

CORE_QUEST="${QUESTS_DIR}/00-core.md"

# True when the user has enabled nothing beyond what ships enabled by default.
# Mirrors _has_any_enabled in existential.sh — caddy ships as true, so "is any
# flag set?" would answer no-one's question. Keep the two in sync.
_defaults_only() {
    local k v
    while IFS='=' read -r k v || [[ -n "$k" ]]; do
        k="${k%%#*}"; k="${k// /}"
        [[ "$k" =~ ^EXIST_IS_ ]] || continue
        v="${v%%#*}"; v="${v// /}"
        [[ "$v" == "true" ]] || continue
        grep -qE "^${k}=true([[:space:]]*#.*)?$" "$EXIST_ENV_TMPL" 2>/dev/null || return 1
    done < "$EXIST_ENV"
    return 0
}

# Enable every service a quest declares. Prints nothing; returns the count via
# the _enabled_count global so the caller can report it.
_enable_quest_services() {
    local _f="$1" _v
    _enabled_count=0
    mapfile -t _qvars < <(qmeta "$_f" '.services[].var // ""' 2>/dev/null | grep -v '^null$\|^$' || true)
    for _v in "${_qvars[@]}"; do
        [[ "$(env_get "$_v")" == "true" ]] && continue
        env_set "$_v" "true"
        _enabled_count=$(( _enabled_count + 1 ))
        _newly_enabled_svcs+=("$(var_to_path "$_v")")
    done
}

# List the template copies a quest would make, as "label\tsrc\tdst" rows, skipping
# any whose `requires:` service is off or whose destination already exists.
# Shared by the Core plan (which shows them, then copies them all) and by
# process_quest_crons (which offers them individually).
#
# Extra args are enablement vars to treat as ALREADY ON. The Core plan needs
# that: it lists what will happen before writing anything, so the services its
# copies require are still false at that point and every row would be filtered
# out. Passing Core's own service vars answers "requires:" against the state the
# user is about to confirm, not the state they are in.
_quest_pending_copies() {
    local _f="$1"; shift
    local _assume=" $* "
    local -a _srcs _dsts _labels _reqs
    mapfile -t _srcs   < <(qmeta "$_f" '.copies[].src      // ""')
    mapfile -t _dsts   < <(qmeta "$_f" '.copies[].dst      // ""')
    mapfile -t _labels < <(qmeta "$_f" '.copies[].label    // ""')
    mapfile -t _reqs   < <(qmeta "$_f" '.copies[].requires // ""')
    local _i _src _dst _req _lbl _fname
    for _i in "${!_srcs[@]}"; do
        _src="${_srcs[$_i]}"
        [[ -z "$_src" || "$_src" == "null" ]] && continue
        _req="${_reqs[$_i]:-}"
        if [[ -n "$_req" && "$_req" != "null" ]]; then
            [[ "$_assume" == *" $_req "* ]] || will_be_active "$_req" || continue
        fi
        [[ -f "${REPO_DIR}/${_src}" ]] || { echo "  ⚠  ${_f##*/}: template not found — ${_src}" >&2; continue; }
        _dst="${_dsts[$_i]}"
        _fname="${_src##*/}"
        [[ -f "${REPO_DIR}/${_dst%/}/${_fname}" ]] && continue
        _lbl="${_labels[$_i]:-}"
        [[ -z "$_lbl" || "$_lbl" == "null" ]] && _lbl="$_fname"
        printf '%s\t%s\t%s\n' "$_lbl" "$_src" "${_dst%/}/"
    done
}

# Copy every pending template for a quest. No prompting: used by the Core path,
# where the templates are part of what Core IS, not a separate decision.
_apply_quest_copies() {
    local _f="$1" _lbl _src _dst _fname
    local _n=0
    while IFS=$'\t' read -r _lbl _src _dst; do
        [[ -z "$_src" ]] && continue
        _fname="${_src##*/}"
        mkdir -p "${REPO_DIR}/${_dst}"
        cp -n "${REPO_DIR}/${_src}" "${REPO_DIR}/${_dst}${_fname}" 2>/dev/null || continue
        _n=$(( _n + 1 ))
    done < <(_quest_pending_copies "$_f")
    # No restart hint: Core runs before `docker compose up -d`, so there is
    # nothing running to restart. process_quest_crons handles the later case.
    _APPLIED_COPIES="$_n"
}

declare -a _newly_enabled_svcs=()
_newly_enabled=0

# _apply_tier <gb> — write a tier's KEY=VALUEs to .env.shared and report it.
# Shared by both paths below so the "No GPU" answer produces exactly the same
# environment as picking the CPU tier by hand would.
# Ask where the remote ollama lives. Chrome to stderr, the answer to stdout, so
# the caller can capture it — same contract as the fzf pickers above.
#
# Validated only for shape, not reachability: the box may well be off right now,
# and refusing to record a correct address because it is asleep would be worse
# than accepting one that is wrong. `./existential.sh test services` is what
# reports whether it actually answers.
_ask_ollama_url() {
    local current="${1:-}" answer
    local default="${current:-http://192.168.1.20:11434}"
    printf '     Where is ollama? [%s]\n     ❯ ' "$default" >&2
    read -r answer
    answer="${answer:-$default}"
    answer="${answer%/}"
    if [[ ! "$answer" =~ ^https?:// ]]; then
        printf '     Not a URL — using %s. Fix it in .env.shared if wrong.\n' "$default" >&2
        answer="$default"
    fi
    printf '%s\n' "$answer"
}

_apply_tier() {
    local _gb="$1" _k _v _tlabel _tchat _tctx _tsize
    while IFS="=" read -r _k _v; do
        [[ -n "$_k" ]] && env_set "$_k" "$_v"
    done < <(model_tier_env "$_gb")
    IFS=$'\t' read -r _ _tlabel _tchat _tctx _tsize _ <<< "$(model_tier_row "$_gb")"
    echo ""
    echo "  ${_C_GREEN}✓${_C_RESET}  ${_tlabel} — ${_tchat} (${_tsize}), ${_tctx} context"
    echo "     Chat, memory extraction and images all use that one model."
    echo "     Change it later:  ./existential.sh run models"
    echo ""
}

# Ask once, on the first run that gets this far. EXIST_GPU_VENDOR is the record
# of having asked, so re-running quest never re-asks — `run models` is the way
# back. Vendor comes first because "none" answers the VRAM question for us.
if [[ -z "$(env_get EXIST_GPU_VENDOR)" ]]; then
    _vendor="$(gpu_vendor_pick "$GPU_VENDOR_DEFAULT")"
    if [[ -n "$_vendor" ]]; then
        env_set EXIST_GPU_VENDOR "$_vendor"
        IFS=$'\t' read -r _ _vlabel _ <<< "$(gpu_vendor_row "$_vendor")"
        echo ""
        echo "  ${_C_GREEN}✓${_C_RESET}  ${_vlabel}"

        if [[ "$_vendor" == "external" ]]; then
            # The models live elsewhere, so nothing local should serve them —
            # a running ollama here would pull multi-GB models onto a machine
            # that never uses them. The VRAM question still applies, because it
            # sizes the models the REMOTE box will hold.
            env_set EXIST_IS_AI_OLLAMA false
            echo "     No local ollama — models come from EXIST_OLLAMA_URL."
            echo ""
            _url="$(_ask_ollama_url "$(env_get EXIST_OLLAMA_URL)")"
            [[ -n "$_url" ]] && env_set EXIST_OLLAMA_URL "$_url"
            echo ""
            echo "     How much VRAM does ${_url:-that machine} have?"
            _picked="$(model_tier_pick "$MODEL_TIER_DEFAULT_GB" --gpu-only)"
            if [[ -n "$_picked" ]]; then
                _apply_tier "$_picked"
            fi
        elif [[ "$_vendor" == "none" ]]; then
            # No card, so there is no VRAM number to ask for. Pin the CPU tier
            # and move on; generate-compose.ts strips the GPU reservations.
            echo "     Everything runs on the CPU — no VRAM question needed."
            _apply_tier 0
        else
            echo ""
            # --gpu-only: "None (CPU)" is not an answer to "how much VRAM",
            # and it is already reachable by re-answering the vendor question.
            _picked="$(model_tier_pick "$MODEL_TIER_DEFAULT_GB" --gpu-only)"
            # A plain `[[ ... ]] && _apply_tier` here would end the block with a
            # false test when the user escapes the picker, and `set -e` would
            # take the whole script down with it.
            if [[ -n "$_picked" ]]; then
                _apply_tier "$_picked"
            fi
        fi
    fi
fi

if _defaults_only && [ -f "$CORE_QUEST" ]; then
    echo ""
    hr
    echo "  ${_C_BOLD}$(qmeta "$CORE_QUEST" '.name')${_C_RESET} — $(qmeta "$CORE_QUEST" '.tagline')"
    hr
    echo ""
    echo "  Everything below runs on your hardware. No API keys, no accounts."
    echo ""
    qmeta "$CORE_QUEST" '.services[].label' | sed 's/^/    • /'
    echo ""
    echo "  Roughly 25 containers, sized to the VRAM you picked: chat, memory and"
    echo "  images share one model on the card, speech-to-text and text-to-speech"
    echo "  run on CPU so they never evict it."
    echo ""

    _core_choice=$(
        {
            printf 'core\t%s✓  Set up Core%s  — the whole system, wired together\n' \
                "$_C_GREEN" "$_C_RESET"
            printf 'browse\t   No thanks  — let me pick services and quests myself\n'
        } | fzf --ansi \
                --delimiter=$'\t' \
                --with-nth=2 \
                --layout=reverse \
                --header="  Start here?
  ↑↓ navigate   Enter confirm" \
                --prompt="Core ❯ " \
                --no-info
    ) || _core_choice=""

    if [[ "${_core_choice%%	*}" == "core" ]]; then
        # Choosing Core is the decision. Everything below follows from it, so
        # show the whole plan and confirm ONCE — never make the templates a
        # second question: without them ollama starts with no models at all.
        echo ""
        hr
        echo "  Here is what Core will do"
        hr
        echo ""
        echo "  Enable these services:"
        qmeta "$CORE_QUEST" '.services[].label' | sed 's/^/    • /'
        # Core enables every service it declares, so answer `requires:` against
        # that set rather than against the not-yet-written .env.shared.
        _core_vars="$(qmeta "$CORE_QUEST" '.services[].var' | tr '\n' ' ')"
        _core_copies="$(_quest_pending_copies "$CORE_QUEST" $_core_vars)"
        if [[ -n "$_core_copies" ]]; then
            echo ""
            echo "  Activate these (models pull themselves; backups start on schedule):"
            cut -f1 <<< "$_core_copies" | sed 's/^/    • /'
        fi
        echo ""
        echo "  Nothing starts yet — this only writes config. You run"
        echo "  docker compose up -d when you are ready."
        echo ""
        read -rp "  Continue? [Y/n] " _core_confirm
        if [[ -n "$_core_confirm" && "${_core_confirm,,}" != "y" && "${_core_confirm,,}" != "yes" ]]; then
            echo ""
            echo "  Nothing changed."
            echo ""
            exit 0
        fi

        _enable_quest_services "$CORE_QUEST"
        _newly_enabled=$(( _newly_enabled + _enabled_count ))
        _apply_quest_copies "$CORE_QUEST"
        echo ""
        echo "  ${_C_GREEN}✓${_C_RESET}  Enabled ${_enabled_count} service(s), activated ${_APPLIED_COPIES} template(s)."
        echo ""
        hr
        echo "  Core — setup guide"
        hr
        echo ""
        _core_guide=$(qbody "$CORE_QUEST")
        if [[ -n "$_core_guide" && "$_core_guide" != "null" ]]; then
            echo "$_core_guide" | sed 's/^/  /'
            echo ""
        fi
        _access_tip
        echo "  Next:  ./existential.sh        (renders config for what you just enabled)"
        echo "         docker compose up -d"
        echo ""
        echo "  More to add later:  ./existential.sh quest"
        echo ""
        exit 0
    fi

    echo ""
    echo "  Fine — here is everything."
fi

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

# Write enabled services to .env.shared (Phase 0 declared the counters)
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
while IFS= read -r f; do _quest_files+=("$f"); done < <(find "$QUESTS_DIR" -name '*.md' -type f | sort)
[ "${#_quest_files[@]}" -gt 0 ] || die "No quest files found in ${QUESTS_DIR}"

_quest_fzf_out=$(
    {
        for _f in "${_quest_files[@]}"; do
            if quest_ready "$_f"; then _qdot="${_C_GREEN}●${_C_RESET}"; else _qdot="${_C_YELLOW}●${_C_RESET}"; fi
            printf '%s\t%s  (%s) %-24s  %s\n' \
                "$_f" "$_qdot" "$(qmeta "$_f" '.services | length')" \
                "$(qmeta "$_f" '.name')" "$(qmeta "$_f" '.tagline')"
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
    mapfile -t _qsvars   < <(qmeta "$_f" '.services[].var // ""' 2>/dev/null | grep -v '^null$\|^$' || true)
    mapfile -t _qslabels < <(qmeta "$_f" '.services[].label // ""' 2>/dev/null | grep -v '^null$\|^$' || true)
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
    _qname="$(qmeta "$_f" '.name')"

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
    _guide=$(qbody "$_f")
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

_access_tip

# Pihole replaces the nip.io lookup with a local answer, so it has one extra
# step the default path does not: pointing the router at it.
if [[ "$_has_pihole" -eq 1 ]]; then
    echo "  You enabled pihole — point your router's DNS at this machine to"
    echo "  finish it, so names resolve locally instead of over the internet:"
    echo "    ./existential.sh run pihole"
    echo ""
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
