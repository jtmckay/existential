#!/usr/bin/env bash
# e2e.sh — end-to-end test harness.
#
# For each selected quest, creates a clean git-archive copy of the repo,
# enables the quest's services, renders templates, generates a unified
# docker-compose, brings it up, runs exist.test.sh for every enabled
# service inside the existential-adhoc container (which shares the
# same Docker network as the services), then tears everything down.
#
# Quests with e2e: false in their YAML require external infrastructure
# (NAS/NFS, DNS, TLS) and are excluded — shown greyed out in the picker.
#
# Usage (via existential.sh):
#   ./existential.sh e2e          # interactive fzf picker (all testable pre-checked)
#   ./existential.sh e2e --all    # non-interactive: run all testable quests
#
# Requirements:
#   - Docker + Docker Compose v2 on the host
#   - No conflicting containers already running (the pre-flight check catches this)

set -euo pipefail
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FIXTURES="${REPO_DIR}/src/test/fixtures"
QUEST_DIR="${REPO_DIR}/src/quests"
E2E_PROJECT="exist-e2e"
E2E_NETWORK="${E2E_PROJECT}_exist"

# ── Quest helpers ─────────────────────────────────────────────────────────────

# List EXIST_IS_* vars for a quest YAML file.
quest_vars() {
    grep '^\s*- var:' "$1" | awk '{print $3}'
}

# Derive service path from EXIST_IS_* var — no lookup table needed.
# EXIST_IS_AI_OPEN_WEBUI        → ai/open-webui
# EXIST_IS_SERVICES_ACTUAL_BUDGET → services/actual-budget
var_to_path() {
    local v="${1#EXIST_IS_}"
    local cat="${v%%_*}"
    local slug="${v#*_}"
    local path="${cat}/${slug//_/-}"
    echo "${path,,}"
}

# Return all numbered quest YAMLs with e2e: true.
automatable_quests() {
    for yaml in "${QUEST_DIR}"/[0-9][0-9]-*.yml; do
        grep -q '^e2e:[[:space:]]*true' "$yaml" && echo "$yaml"
    done
}

# ── Helpers ───────────────────────────────────────────────────────────────────

log()  { printf '\n[e2e] %s\n' "$*"; }
die()  { printf '\n[e2e] FATAL: %s\n' "$*" >&2; exit 1; }
hr()   { printf '[e2e] '; printf '%0.s─' {1..54}; echo; }

wait_running() {
    local work="$1" timeout="${2:-30}"
    local deadline=$(( $(date +%s) + timeout ))
    log "Waiting for containers to stabilize (up to ${timeout}s)..."
    while [ "$(date +%s)" -lt "$deadline" ]; do
        local total running in_progress
        total=$(docker compose -p "$E2E_PROJECT" -f "$work/docker-compose.yml" \
                    ps -q 2>/dev/null | wc -l | tr -d ' ')
        running=$(docker compose -p "$E2E_PROJECT" -f "$work/docker-compose.yml" \
                    ps -q --status running 2>/dev/null | wc -l | tr -d ' ')
        # "created" and "restarting" are transitional — wait them out
        in_progress=$(docker compose -p "$E2E_PROJECT" -f "$work/docker-compose.yml" \
                    ps -q --status created --status restarting 2>/dev/null | wc -l | tr -d ' ')
        if [ "$total" -gt 0 ] && [ "$in_progress" -eq 0 ]; then
            echo
            if [ "$total" -ne "$running" ]; then
                log "$(( total - running )) container(s) not running — proceeding to tests"
                docker compose -p "$E2E_PROJECT" -f "$work/docker-compose.yml" ps || true
            fi
            return 0
        fi
        printf '.'
        sleep 2
    done
    echo
    log "Timeout — current container state:"
    docker compose -p "$E2E_PROJECT" -f "$work/docker-compose.yml" ps || true
    return 1
}

# ── Pre-flight collision detection ────────────────────────────────────────────

preflight_check() {
    local -a yaml_files=("$@")
    local errors=0

    # Collect every container_name from compose files for the selected quests
    declare -a wanted=()
    for yaml in "${yaml_files[@]}"; do
        for var in $(quest_vars "$yaml"); do
            local path; path=$(var_to_path "$var")
            local compose="${REPO_DIR}/${path}/docker-compose.exist.yml"
            [ -f "$compose" ] || continue
            while IFS= read -r name; do
                [[ -n "$name" ]] && wanted+=("$name")
            done < <(grep -E '^\s+container_name:' "$compose" 2>/dev/null | awk '{print $NF}')
        done
    done
    wanted+=("existential-adhoc")

    local existing
    existing=$(docker ps -a --format '{{.Names}}' 2>/dev/null || true)

    local stale_network=0
    if docker network inspect "$E2E_NETWORK" >/dev/null 2>&1; then
        stale_network=1; errors=$(( errors + 1 ))
    fi

    declare -a collisions=()
    for name in "${wanted[@]}"; do
        if echo "$existing" | grep -qxF "$name"; then
            local state
            state=$(docker inspect --format '{{.State.Status}}' "$name" 2>/dev/null || echo "unknown")
            collisions+=("${name} (${state})")
            errors=$(( errors + 1 ))
        fi
    done

    if [ "$errors" -eq 0 ]; then
        log "Pre-flight OK"
        return 0
    fi

    echo ""
    echo "[e2e] ✗ PRE-FLIGHT FAILED — conflicting containers or stale network found."
    echo ""
    if [ "${#collisions[@]}" -gt 0 ]; then
        echo "[e2e]   Containers:"
        for c in "${collisions[@]}"; do echo "[e2e]     $c"; done
        echo ""
    fi
    [ "$stale_network" -eq 1 ] && { echo "[e2e]   Network:  ${E2E_NETWORK} (stale)"; echo ""; }
    echo "[e2e]   If these are your real stack containers, stop them first:"
    echo "[e2e]     docker compose down"
    echo ""

    local names_only=()
    for c in "${collisions[@]}"; do names_only+=("${c% (*)}"); done

    if [ -t 0 ]; then
        echo "[e2e]   Press Enter to remove the above and continue (Ctrl-C to abort)."
        echo "[e2e]   Note: only containers are removed — named and NFS volumes are untouched."
        printf '[e2e] > '
        read -r _
        [ "${#names_only[@]}" -gt 0 ] && docker rm -f "${names_only[@]}" >/dev/null
        docker network rm "$E2E_NETWORK" >/dev/null 2>&1 || true
        log "Pre-flight OK (cleaned up)"
        return 0
    fi

    echo "[e2e]   To remove:"
    [ "${#names_only[@]}" -gt 0 ] && echo "[e2e]     docker rm -f ${names_only[*]}"
    [ "$stale_network" -eq 1 ]    && echo "[e2e]     docker network rm ${E2E_NETWORK}"
    return 1
}

# ── Per-quest runner ──────────────────────────────────────────────────────────

WORK=""

cleanup() {
    if [ -n "$WORK" ] && [ -f "$WORK/docker-compose.yml" ]; then
        log "Tearing down..."
        docker compose -p "$E2E_PROJECT" -f "$WORK/docker-compose.yml" down -v \
            --remove-orphans 2>/dev/null || true
    fi
    docker network rm "$E2E_NETWORK" 2>/dev/null || true
    [ -n "$WORK" ] && [ -d "$WORK" ] && rm -rf "$WORK"
    WORK=""
}
trap cleanup EXIT INT TERM

run_quest() {
    local yaml="$1"
    local quest_name; quest_name=$(grep '^name:' "$yaml" | sed 's/^name:[[:space:]]*//')

    hr
    log "${quest_name} — start"
    hr

    WORK="${REPO_DIR}/.tmp-e2e-$(date '+%Y-%m-%d_%H-%M')-$$"
    mkdir -p "$WORK"

    # 1. Fresh clone from git archive (tracked files only, no secrets)
    log "Creating fresh clone..."
    git -C "$REPO_DIR" archive HEAD | tar -x -C "$WORK"

    # 2. Pre-fill .env.shared from fixture (bypasses EXIST_CLI prompts)
    cp "$FIXTURES/env.shared" "$WORK/.env.shared"

    # 3. Enable this quest's services
    log "Enabling services..."
    for var in $(quest_vars "$yaml"); do
        sed -i "s|^${var}=false|${var}=true|" "$WORK/.env.shared"
    done

    # 4. Render service templates (non-interactive — .env.shared already present)
    log "Rendering templates..."
    docker compose -p "$E2E_PROJECT" -f "$WORK/existential-compose.yml" run --rm \
        --entrypoint "" \
        -e REPO_DIR=/repo \
        -e FORCE=false \
        existential-adhoc \
        bash /src/templates.sh

    # 5. Generate unified docker-compose.yml
    # Pass $WORK as the host-side repo root so generate-compose.ts can write
    # absolute bind-mount paths that resolve correctly when docker compose up
    # runs on the host (not inside the adhoc container).
    log "Generating docker-compose.yml..."
    docker compose -p "$E2E_PROJECT" -f "$WORK/existential-compose.yml" run --rm \
        --entrypoint "" existential-adhoc \
        tsx /src/generate-compose.ts /repo docker-compose.yml "$WORK"

    [ -f "$WORK/docker-compose.yml" ] || die "generate-compose.ts produced no docker-compose.yml"

    # 6. Bring services up
    log "Starting services..."
    docker compose -p "$E2E_PROJECT" -f "$WORK/docker-compose.yml" up -d

    # 7. Wait for containers to stabilize
    wait_running "$WORK"

    # 8. Run per-service tests
    log "Running service tests for ${quest_name}:"
    local e2e_paths=""
    for var in $(quest_vars "$yaml"); do
        local svc_path; svc_path=$(var_to_path "$var")
        if [ -f "$WORK/${svc_path}/exist.test.sh" ]; then
            log "  • ${svc_path}/exist.test.sh"
            e2e_paths="${e2e_paths:+${e2e_paths}:}${svc_path}"
        fi
    done
    docker compose -p "$E2E_PROJECT" -f "$WORK/existential-compose.yml" run --rm \
        -e E2E_MODE=1 \
        -e "E2E_SERVICE_PATHS=${e2e_paths}" \
        --entrypoint "" existential-adhoc \
        bash /src/test/run-all.sh

    log "${quest_name} — PASSED"
    cleanup
}

# ── Main ──────────────────────────────────────────────────────────────────────

# Build adhoc image once — used for template rendering, compose gen, and tests.
log "Building existential-adhoc image..."
docker compose -p "$E2E_PROJECT" -f "${REPO_DIR}/existential-compose.yml" build existential-adhoc

# Quest selection
declare -a SELECTED_YAMLS=()

if [ "${1:-}" = "--all" ] || [ ! -t 0 ]; then
    # Non-interactive: run every automatable quest
    mapfile -t SELECTED_YAMLS < <(automatable_quests)
    [ "${#SELECTED_YAMLS[@]}" -gt 0 ] || die "No automatable quests found."
elif command -v fzf >/dev/null 2>&1; then
    # fzf on host — draw picker directly (fzf uses /dev/tty for UI, safe in <(...))
    _excl_header="Excluded (require manual setup):"
    for _y in "${QUEST_DIR}"/[0-9][0-9]-*.yml; do
        grep -q '^e2e:[[:space:]]*false' "$_y" || continue
        _n=$(grep '^name:' "$_y" | sed 's/^name:[[:space:]]*//')
        _excl_header+=$'\n'"  ✗ ${_n}"
    done
    _excl_header+=$'\n─────────────────────────────────────────────────────\nSpace/Tab to toggle  ·  Enter to confirm'
    mapfile -t SELECTED_YAMLS < <(
        automatable_quests | while IFS= read -r _y; do
            _n=$(grep '^name:' "$_y" | sed 's/^name:[[:space:]]*//')
            printf '%s\t%s\n' "$_y" "$_n"
        done | fzf --multi --no-sort \
                   --with-nth=2 \
                   --prompt="  e2e ❯ " \
                   --bind 'start:select-all' \
                   --header-first \
                   --header="$_excl_header" \
            | cut -f1
    )
    [ "${#SELECTED_YAMLS[@]}" -gt 0 ] || die "No quests selected."
else
    # No fzf — numbered prompt
    declare -a _all=()
    mapfile -t _all < <(automatable_quests)
    [ "${#_all[@]}" -gt 0 ] || die "No automatable quests found."
    echo ""
    for _i in "${!_all[@]}"; do
        _n=$(grep '^name:' "${_all[$_i]}" | sed 's/^name:[[:space:]]*//')
        printf '[e2e]   %d) %s\n' "$(( _i + 1 ))" "$_n"
    done
    echo ""
    printf '[e2e] Run which? Enter numbers (e.g. 1 3) or blank for all: '
    read -r _choice
    if [ -z "$_choice" ]; then
        SELECTED_YAMLS=("${_all[@]}")
    else
        for _n in $_choice; do
            _idx=$(( _n - 1 ))
            [ "$_idx" -ge 0 ] && [ "$_idx" -lt "${#_all[@]}" ] && SELECTED_YAMLS+=("${_all[$_idx]}")
        done
    fi
    [ "${#SELECTED_YAMLS[@]}" -gt 0 ] || die "No quests selected."
fi

log "Selected quests:"
for yaml in "${SELECTED_YAMLS[@]}"; do
    name=$(grep '^name:' "$yaml" | sed 's/^name:[[:space:]]*//')
    log "  • ${name}"
done

preflight_check "${SELECTED_YAMLS[@]}"

declare -a PASS=() FAIL=()

for yaml in "${SELECTED_YAMLS[@]}"; do
    name=$(grep '^name:' "$yaml" | sed 's/^name:[[:space:]]*//')
    if run_quest "$yaml"; then
        PASS+=("$name")
    else
        FAIL+=("$name")
        log "${name} — FAILED"
        cleanup
    fi
done

hr
log "Results: ${#PASS[@]} passed, ${#FAIL[@]} failed"
[ "${#PASS[@]}" -gt 0 ] && log "  Passed: ${PASS[*]}"
[ "${#FAIL[@]}" -gt 0 ] && log "  Failed: ${FAIL[*]}"
hr

[ "${#FAIL[@]}" -eq 0 ]
