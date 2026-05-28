#!/usr/bin/env bash
# Quest picker + onboarding guide.
# Runs on the host. Reads/writes EXIST_IS_* flags in ${REPO_DIR}/.env.shared.
# Invoked by: ./existential.sh quest
#
# Flow:
#   1. Pick quests (themed bundles)
#   2. Customize service checklist (toggle recommended services on/off)
#   3. Read the quest guide (contextual setup steps + cron templates)
#   4. Confirm → flags written, existential.sh continues with setup

set -euo pipefail

REPO_DIR="${REPO_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
EXIST_ENV="${REPO_DIR}/.env.shared"

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

# ── Quest metadata ─────────────────────────────────────────────────────────────

QUEST_COUNT=8

quest_name() {
    case "$1" in
        1) echo "Local AI Lab" ;;            2) echo "Smart Home" ;;
        3) echo "Home Finance" ;;            4) echo "Media & Files" ;;
        5) echo "Productivity & Tools" ;;   6) echo "Homelab Infrastructure" ;;
        7) echo "Network Access" ;;         8) echo "NAS Storage" ;;
    esac
}

quest_tagline() {
    case "$1" in
        1) echo "Chat with local LLMs, transcribe audio, connect tools to your AI" ;;
        2) echo "Automate your home, get notified, and wire up routines" ;;
        3) echo "Track spending and plan meals without a subscription" ;;
        4) echo "Host your photos, files, and documents yourself" ;;
        5) echo "Tasks, databases, and low-code apps" ;;
        6) echo "Monitoring, containers, and dashboards" ;;
        7) echo "DNS + reverse proxy — makes every service reachable at https://<slug>.internal" ;;
        8) echo "Wire up TrueNAS NFS mounts for services that need persistent NAS-backed storage" ;;
    esac
}

quest_vars() {
    case "$1" in
        1) echo "EXIST_IS_AI_OLLAMA EXIST_IS_AI_OPEN_WEBUI EXIST_IS_AI_MCP \
                 EXIST_IS_AI_HERMES EXIST_IS_AI_WHISPER EXIST_IS_AI_LIGHTRAG \
                 EXIST_IS_AI_CHATTERBOX" ;;
        2) echo "EXIST_IS_SERVICES_HOMEASSISTANT EXIST_IS_SERVICES_DECREE \
                 EXIST_IS_SERVICES_NTFY" ;;
        3) echo "EXIST_IS_SERVICES_ACTUAL_BUDGET EXIST_IS_SERVICES_MEALIE" ;;
        4) echo "EXIST_IS_SERVICES_IMMICH EXIST_IS_NAS_NEXTCLOUD \
                 EXIST_IS_NAS_MINIO EXIST_IS_NAS_COLLABORA" ;;
        5) echo "EXIST_IS_SERVICES_VIKUNJA EXIST_IS_SERVICES_NOCODB \
                 EXIST_IS_SERVICES_APPSMITH EXIST_IS_SERVICES_LOWCODER \
                 EXIST_IS_SERVICES_IT_TOOLS" ;;
        6) echo "EXIST_IS_HOSTING_PORTAINER EXIST_IS_HOSTING_GRAFANA \
                 EXIST_IS_HOSTING_PROMETHEUS EXIST_IS_HOSTING_LOKI \
                 EXIST_IS_HOSTING_UPTIME_KUMA EXIST_IS_SERVICES_DASHY \
                 EXIST_IS_SERVICES_DECREE" ;;
        7) echo "EXIST_IS_HOSTING_PIHOLE EXIST_IS_HOSTING_CADDY" ;;
        8) echo "" ;;  # guide-only — no service flags to toggle
    esac
}

var_label() {
    case "$1" in
        EXIST_IS_AI_OLLAMA)               echo "Ollama" ;;
        EXIST_IS_AI_OPEN_WEBUI)           echo "Open WebUI" ;;
        EXIST_IS_AI_MCP)                  echo "MCP" ;;
        EXIST_IS_AI_HERMES)               echo "Hermes" ;;
        EXIST_IS_AI_WHISPER)              echo "Whisper" ;;
        EXIST_IS_AI_LIGHTRAG)             echo "LightRAG" ;;
        EXIST_IS_AI_CHATTERBOX)           echo "Chatterbox" ;;
        EXIST_IS_SERVICES_HOMEASSISTANT)  echo "Home Assistant" ;;
        EXIST_IS_SERVICES_DECREE)         echo "Decree" ;;
        EXIST_IS_SERVICES_NTFY)           echo "ntfy" ;;
        EXIST_IS_SERVICES_ACTUAL_BUDGET)  echo "Actual Budget" ;;
        EXIST_IS_SERVICES_MEALIE)         echo "Mealie" ;;
        EXIST_IS_SERVICES_IMMICH)         echo "Immich" ;;
        EXIST_IS_NAS_NEXTCLOUD)           echo "Nextcloud" ;;
        EXIST_IS_NAS_MINIO)               echo "MinIO" ;;
        EXIST_IS_NAS_COLLABORA)           echo "Collabora" ;;
        EXIST_IS_SERVICES_VIKUNJA)        echo "Vikunja" ;;
        EXIST_IS_SERVICES_NOCODB)         echo "NocoDB" ;;
        EXIST_IS_SERVICES_APPSMITH)       echo "Appsmith" ;;
        EXIST_IS_SERVICES_LOWCODER)       echo "Lowcoder" ;;
        EXIST_IS_SERVICES_IT_TOOLS)       echo "IT Tools" ;;
        EXIST_IS_HOSTING_PIHOLE)          echo "Pihole" ;;
        EXIST_IS_HOSTING_CADDY)           echo "Caddy" ;;
        EXIST_IS_HOSTING_PORTAINER)       echo "Portainer" ;;
        EXIST_IS_HOSTING_GRAFANA)         echo "Grafana" ;;
        EXIST_IS_HOSTING_PROMETHEUS)      echo "Prometheus" ;;
        EXIST_IS_HOSTING_LOKI)            echo "Loki" ;;
        EXIST_IS_HOSTING_UPTIME_KUMA)     echo "Uptime Kuma" ;;
        EXIST_IS_SERVICES_DASHY)          echo "Dashy" ;;
        *)                                echo "$1" ;;
    esac
}

# Filesystem path for the service (relative to REPO_DIR)
var_path() {
    case "$1" in
        EXIST_IS_AI_OLLAMA)               echo "ai/ollama" ;;
        EXIST_IS_AI_OPEN_WEBUI)           echo "ai/open-webui" ;;
        EXIST_IS_AI_MCP)                  echo "ai/mcp" ;;
        EXIST_IS_AI_HERMES)               echo "ai/hermes" ;;
        EXIST_IS_AI_WHISPER)              echo "ai/whisper" ;;
        EXIST_IS_AI_LIGHTRAG)             echo "ai/lightrag" ;;
        EXIST_IS_AI_CHATTERBOX)           echo "ai/chatterbox" ;;
        EXIST_IS_SERVICES_HOMEASSISTANT)  echo "services/homeassistant" ;;
        EXIST_IS_SERVICES_DECREE)         echo "services/decree" ;;
        EXIST_IS_SERVICES_NTFY)           echo "services/ntfy" ;;
        EXIST_IS_SERVICES_ACTUAL_BUDGET)  echo "services/actual-budget" ;;
        EXIST_IS_SERVICES_MEALIE)         echo "services/mealie" ;;
        EXIST_IS_SERVICES_IMMICH)         echo "services/immich" ;;
        EXIST_IS_NAS_NEXTCLOUD)           echo "nas/nextcloud" ;;
        EXIST_IS_NAS_MINIO)               echo "nas/minio" ;;
        EXIST_IS_NAS_COLLABORA)           echo "nas/collabora" ;;
        EXIST_IS_SERVICES_VIKUNJA)        echo "services/vikunja" ;;
        EXIST_IS_SERVICES_NOCODB)         echo "services/nocodb" ;;
        EXIST_IS_SERVICES_APPSMITH)       echo "services/appsmith" ;;
        EXIST_IS_SERVICES_LOWCODER)       echo "services/lowcoder" ;;
        EXIST_IS_SERVICES_IT_TOOLS)       echo "services/it-tools" ;;
        EXIST_IS_HOSTING_PIHOLE)          echo "hosting/pihole" ;;
        EXIST_IS_HOSTING_CADDY)           echo "hosting/caddy" ;;
        EXIST_IS_HOSTING_PORTAINER)       echo "hosting/portainer" ;;
        EXIST_IS_HOSTING_GRAFANA)         echo "hosting/grafana" ;;
        EXIST_IS_HOSTING_PROMETHEUS)      echo "hosting/prometheus" ;;
        EXIST_IS_HOSTING_LOKI)            echo "hosting/loki" ;;
        EXIST_IS_HOSTING_UPTIME_KUMA)     echo "hosting/uptime-kuma" ;;
        EXIST_IS_SERVICES_DASHY)          echo "services/dashy" ;;
    esac
}

# ── Phase 1: Quest selection ───────────────────────────────────────────────────

hr
echo "  Pick a quest — what do you want to build?"
hr
echo ""
for i in $(seq 1 $QUEST_COUNT); do
    printf "  [%d]  %s\n" "$i" "$(quest_name "$i")"
    printf "       %s\n" "$(quest_tagline "$i")"
    echo ""
done

read -rp "Quests (space-separated, e.g. 1 3 6): " _quest_input
[ -n "$_quest_input" ] || { echo "Nothing selected."; exit 0; }

declare -a _active_quests=()
declare -A _quest_seen=()
for _q in $_quest_input; do
    [[ "$_q" =~ ^[0-9]+$ ]] || die "Invalid: '${_q}' is not a number"
    [[ "$_q" -ge 1 && "$_q" -le "$QUEST_COUNT" ]] || die "Quest ${_q} out of range (1–${QUEST_COUNT})"
    [[ "${_quest_seen[$_q]:-}" == "1" ]] && continue
    _quest_seen[$_q]=1
    _active_quests+=("$_q")
done

# ── Phase 2: Build service list + checklist ────────────────────────────────────

declare -a CL_VARS=()        # ordered list of vars in the checklist
declare -A CL_SEEN=()        # dedup guard
declare -A CL_ENABLED=()     # var → 1 if currently true in .env.shared
declare -A CL_SELECTED=()    # var → 1 if the user wants it enabled

for _q in "${_active_quests[@]}"; do
    for _var in $(quest_vars "$_q"); do
        [[ "${CL_SEEN[$_var]:-}" == "1" ]] && continue
        CL_SEEN[$_var]=1
        CL_VARS+=("$_var")
        [[ "$(env_get "$_var")" == "true" ]] && CL_ENABLED[$_var]=1 || true
        CL_SELECTED[$_var]=1   # start pre-checked
    done
done

# Quest 8 (NAS Storage) has no service flags — it's guide-only.
_guide_only=0
[ "${#CL_VARS[@]}" -gt 0 ] || _guide_only=1

if [ "$_guide_only" -eq 1 ]; then
    echo ""
    echo "  Quest ${_active_quests[*]} has no service flags — skipping to guide."
fi

# Build header title from quest names
_quest_title() {
    local titles=()
    for _q in "${_active_quests[@]}"; do titles+=("$(quest_name "$_q")"); done
    ( IFS=' + '; echo "${titles[*]}" )
}

print_checklist() {
    echo ""
    hr
    printf "  %s\n" "$(_quest_title)"
    hr
    echo ""
    echo "  Recommended services — toggle with numbers, enter to confirm:"
    echo ""
    local i=1
    for _var in "${CL_VARS[@]}"; do
        local label
        label="$(var_label "$_var")"
        if [[ "${CL_ENABLED[$_var]:-}" == "1" ]]; then
            printf "  [✓] %2d.  %-24s  already enabled\n" "$i" "$label"
        elif [[ "${CL_SELECTED[$_var]:-}" == "1" ]]; then
            printf "  [✓] %2d.  %-24s\n" "$i" "$label"
        else
            printf "  [ ] %2d.  %-24s\n" "$i" "$label"
        fi
        i=$((i + 1))
    done
    echo ""
}

# Interactive toggle loop — re-display after each batch of toggles
declare -a NEW_VARS=()

if [ "$_guide_only" -eq 0 ]; then
print_checklist
while true; do
    read -rp "  Toggle (enter numbers to flip, or press enter to confirm): " _toggle_input
    [[ -z "$_toggle_input" ]] && break
    for _num in $_toggle_input; do
        [[ "$_num" =~ ^[0-9]+$ ]] || continue
        _idx=$((_num - 1))
        [ "$_idx" -ge 0 ] && [ "$_idx" -lt "${#CL_VARS[@]}" ] || continue
        _var="${CL_VARS[$_idx]}"
        [[ "${CL_ENABLED[$_var]:-}" == "1" ]] && continue   # already enabled → not toggleable
        if [[ "${CL_SELECTED[$_var]:-}" == "1" ]]; then
            CL_SELECTED[$_var]=0
        else
            CL_SELECTED[$_var]=1
        fi
    done
    print_checklist
done

# Collect vars that will be newly enabled
declare -a NEW_VARS=()
for _var in "${CL_VARS[@]}"; do
    if [[ "${CL_ENABLED[$_var]:-}" != "1" && "${CL_SELECTED[$_var]:-}" == "1" ]]; then
        NEW_VARS+=("$_var")
    fi
done

if [ "${#NEW_VARS[@]}" -eq 0 ]; then
    echo "  All selected services are already enabled. Nothing to do."
    exit 0
fi
fi  # end if [ "$_guide_only" -eq 0 ]

# ── Phase 3: Quest guide ───────────────────────────────────────────────────────
# Show contextual guidance based on what's being enabled.
# Already-enabled services are included in context checks (they may interact
# with newly-enabled ones), but commands are only shown when relevant.

# Helper: is a var in the final "will be active" set (enabled OR newly selected)?
will_be_active() {
    [[ "${CL_ENABLED[$1]:-}" == "1" || "${CL_SELECTED[$1]:-}" == "1" ]]
}

# Determine relevant flags
_has_pihole=0;  will_be_active EXIST_IS_HOSTING_PIHOLE   && _has_pihole=1   || true
_has_caddy=0;   will_be_active EXIST_IS_HOSTING_CADDY    && _has_caddy=1    || true
_has_decree=0;  will_be_active EXIST_IS_SERVICES_DECREE  && _has_decree=1   || true
_has_budget=0;  will_be_active EXIST_IS_SERVICES_ACTUAL_BUDGET && _has_budget=1 || true
_has_ntfy=0;    will_be_active EXIST_IS_SERVICES_NTFY    && _has_ntfy=1     || true

# Count vars with sidecar cron templates (among newly-enabling only)
_has_backup_candidates=0
for _var in "${NEW_VARS[@]}"; do
    _svc_path="$(var_path "$_var" 2>/dev/null || true)"
    [ -n "$_svc_path" ] || continue
    [ -d "${REPO_DIR}/${_svc_path}/decree/cron.example" ] && { _has_backup_candidates=1; break; } || true
done

# Check for decree sidecar crons among ALL selected (not just new)
_has_any_sidecar_cron=0
for _var in "${CL_VARS[@]}"; do
    [[ "${CL_SELECTED[$_var]:-}" == "1" ]] || continue
    _svc_path="$(var_path "$_var" 2>/dev/null || true)"
    [ -n "$_svc_path" ] || continue
    [ -d "${REPO_DIR}/${_svc_path}/decree/cron.example" ] && { _has_any_sidecar_cron=1; break; } || true
done

echo ""
hr
echo "  Quest guide — $(_quest_title)"
hr

# -- Automatic setup (runs with ./existential.sh) --
echo ""
echo "  ── What ./existential.sh handles automatically ──────────────"
echo ""
echo "  Renders config templates for all newly-enabled services."
_auto_initials=()
for _var in "${NEW_VARS[@]}"; do
    _svc_path="$(var_path "$_var" 2>/dev/null || true)"
    [ -n "$_svc_path" ] || continue
    [ -f "${REPO_DIR}/${_svc_path}/exist.initial.sh" ] || continue
    _slug="${_svc_path##*/}"
    _auto_initials+=("$_slug")
done
if [ "${#_auto_initials[@]}" -gt 0 ]; then
    echo "  Runs interactive first-time setup for:"
    for _s in "${_auto_initials[@]}"; do
        echo "    ./existential.sh run ${_s}   (re-run anytime to reconfigure)"
    done
fi
echo ""

# -- Optional: integrations & run scripts --
_run_steps=()

if [[ "$_has_backup_candidates" -eq 1 ]]; then
    _run_steps+=("── Backup storage (required before activating backup crons) ──────")
    _run_steps+=("  ./existential.sh run rclone    # add a cloud storage remote (MinIO, S3, Dropbox…)")
    _run_steps+=("  ./existential.sh run backup-config    # choose the destination path on that remote")
    _run_steps+=("")
fi

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
    echo "  ── Optional setup scripts (run after services start) ─────────"
    echo ""
    for _line in "${_run_steps[@]}"; do
        echo "  ${_line}"
    done
fi

# -- Cron templates --
_cron_blocks=()

# Per-service sidecar crons (only for newly-enabling services)
for _var in "${NEW_VARS[@]}"; do
    _svc_path="$(var_path "$_var" 2>/dev/null || true)"
    [ -n "$_svc_path" ] || continue
    _slug="${_svc_path##*/}"
    _cron_dir="${REPO_DIR}/${_svc_path}/decree/cron.example"
    [ -d "$_cron_dir" ] || continue

    _templates=()
    while IFS= read -r _f; do
        _templates+=("${_f##*/}")
    done < <(find "$_cron_dir" -maxdepth 1 -name "*.md" -type f 2>/dev/null | sort)
    [ "${#_templates[@]}" -eq 0 ] && continue

    _cron_blocks+=("  ${_slug}:")
    for _tmpl in "${_templates[@]}"; do
        _cron_blocks+=("    cp ${_svc_path}/decree/cron.example/${_tmpl} \\")
        _cron_blocks+=("       ${_svc_path}/decree/cron/")
    done
    _cron_blocks+=("    docker compose restart ${_slug}-decree")
    _cron_blocks+=("")
done

# Main decree daemon crons (if decree is newly being enabled)
if [[ "${CL_ENABLED[EXIST_IS_SERVICES_DECREE]:-}" != "1" && "${CL_SELECTED[EXIST_IS_SERVICES_DECREE]:-}" == "1" ]]; then
    _decree_cron_dir="${REPO_DIR}/services/decree/decree/cron.example"
    if [ -d "$_decree_cron_dir" ]; then
        _templates=()
        while IFS= read -r _f; do
            _templates+=("${_f##*/}")
        done < <(find "$_decree_cron_dir" -maxdepth 1 -name "*.md" -type f 2>/dev/null | sort)
        if [ "${#_templates[@]}" -gt 0 ]; then
            _cron_blocks+=("  decree (main daemon):")
            for _tmpl in "${_templates[@]}"; do
                _cron_blocks+=("    cp services/decree/decree/cron.example/${_tmpl} \\")
                _cron_blocks+=("       services/decree/decree/cron/")
            done
            _cron_blocks+=("    docker compose restart decree")
            _cron_blocks+=("")
        fi
    fi
fi

if [ "${#_cron_blocks[@]}" -gt 0 ]; then
    echo "  ── Cron job templates (copy to activate) ─────────────────────"
    echo "  Schedule defaults are in each template's frontmatter — edit"
    echo "  the file before copying if you want a different schedule."
    echo ""
    for _line in "${_cron_blocks[@]}"; do
        echo "  ${_line}"
    done
fi

# -- NAS Storage --
_has_nas_storage=0
for _q in "${_active_quests[@]}"; do [[ "$_q" == "8" ]] && _has_nas_storage=1 || true; done

if [[ "$_has_nas_storage" -eq 1 ]]; then
    echo "  ── NAS Storage (TrueNAS) ──────────────────────────────────────"
    echo ""
    echo "  Services in Quest 4 (Nextcloud, MinIO, Collabora) can use NFS"
    echo "  volumes backed by TrueNAS instead of plain local storage."
    echo ""
    echo "  1. Set in .env.shared (or re-run ./existential.sh to be prompted):"
    echo "       EXIST_TRUENAS_SERVER_ADDRESS=<your-truenas-ip>"
    echo "       EXIST_TRUENAS_CONTAINER_PATH=<nfs-export-base-path>"
    echo ""
    echo "  2. Re-render templates to uncomment NFS volume blocks:"
    echo "       ./existential.sh --force templates"
    echo ""
    echo "  NFS volumes are automatically commented out when TrueNAS is not"
    echo "  configured — services fall back to plain named volumes."
    echo ""
fi

# -- DNS & access --
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

# Guide-only quests (e.g. Quest 8) stop here — nothing to enable.
[ "$_guide_only" -eq 0 ] || exit 0

# ── Phase 4: Confirm + write flags ────────────────────────────────────────────

hr
echo ""
_labels=()
for _var in "${NEW_VARS[@]}"; do _labels+=("$(var_label "$_var")"); done
printf "  Enabling %d service(s): %s\n" "${#NEW_VARS[@]}" "$(IFS=', '; echo "${_labels[*]}")"
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
