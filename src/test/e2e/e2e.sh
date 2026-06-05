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
#   ./existential.sh e2e                 # interactive fzf picker (all testable pre-checked)
#   ./existential.sh e2e --all           # non-interactive: run all testable quests
#   ./existential.sh e2e automation      # run quests whose name/filename matches a pattern
#   ./existential.sh e2e ai finance      # multiple patterns — each selects matching quest(s)
#   ./existential.sh e2e down            # tear down leftover artifacts from a crashed run
#
# Requirements:
#   - Docker + Docker Compose v2 on the host
#   - No conflicting containers already running (the pre-flight check catches this)

set -euo pipefail
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
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

# Resolve name patterns (e.g. "automation" or "ai finance") to automatable
# quest YAML paths. Each pattern is matched case-insensitively against the
# quest's `name:` field and its filename. A pattern that matches only a
# non-e2e quest (one needing manual NAS/DNS/TLS setup) reports why it's
# skipped; a pattern that matches nothing is warned about. Output may contain
# duplicates — the caller dedupes while preserving order.
quest_name() { grep '^name:' "$1" | sed 's/^name:[[:space:]]*//'; }

quests_by_names() {
    local -a all=()
    mapfile -t all < <(automatable_quests)
    local pat yaml found hit
    for pat in "$@"; do
        found=""
        for yaml in "${all[@]}"; do
            if grep -qi -- "$pat" <<<"$(quest_name "$yaml")" \
            || grep -qi -- "$pat" <<<"$(basename "$yaml" .yml)"; then
                echo "$yaml"; found=1
            fi
        done
        [ -n "$found" ] && continue
        # No e2e-able match — was it a non-e2e quest, or just a typo?
        hit=""
        for yaml in "${QUEST_DIR}"/[0-9][0-9]-*.yml; do
            if grep -qi -- "$pat" <<<"$(quest_name "$yaml")" \
            || grep -qi -- "$pat" <<<"$(basename "$yaml" .yml)"; then
                hit=$(quest_name "$yaml"); break
            fi
        done
        if [ -n "$hit" ]; then
            log "'${pat}' matched \"${hit}\" but that quest isn't e2e-able (needs manual setup) — skipped" >&2
        else
            log "No quest matched '${pat}' — skipped" >&2
        fi
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

# Remove leftover .tmp-e2e-* work dirs from a previously crashed run. They may
# contain root-owned volume data (containers run as root), so reclaim with a
# throwaway root container first, then rm the dir on the host. Returns the count
# removed via the global _SWEPT so callers can report "found something".
_SWEPT=0
sweep_leftover_workdirs() {
    _SWEPT=0
    local -a stale=()
    mapfile -t stale < <(find "$REPO_DIR" -maxdepth 1 -type d -name '.tmp-e2e-*' 2>/dev/null)
    [ "${#stale[@]}" -gt 0 ] || return 0
    local d
    for d in "${stale[@]}"; do
        log "Reclaiming leftover work dir ${d##*/}..."
        docker run --rm -u 0 -v "${d}:/cleanup" alpine \
            sh -c 'rm -rf /cleanup/* /cleanup/.[!.]* 2>/dev/null' 2>/dev/null || true
        if rm -rf "$d" 2>/dev/null; then
            _SWEPT=$(( _SWEPT + 1 ))
        else
            log "  warn: could not fully remove ${d##*/} — stale root-owned files may remain"
        fi
    done
}

# ── Teardown of leftover artifacts ──────────────────────────────────────────────
# `./existential.sh e2e down` — find every container, network, volume, and temp
# work dir belonging to a previous e2e run (compose project "exist-e2e") and spin
# it down. The normal per-quest cleanup() handles the happy path; this is the
# recovery hatch for a run that crashed before its trap fired and left artifacts
# behind. Everything is keyed off the compose project label, so it never touches
# the real stack.
e2e_down() {
    local found=0

    # Containers carry com.docker.compose.project=exist-e2e (set by `-p`).
    local -a ids=()
    mapfile -t ids < <(docker ps -aq --filter "label=com.docker.compose.project=${E2E_PROJECT}" 2>/dev/null)
    if [ "${#ids[@]}" -gt 0 ]; then
        found=1
        local id name
        for id in "${ids[@]}"; do
            name=$(docker inspect --format '{{.Name}}' "$id" 2>/dev/null | sed 's#^/##')
            log "Spinning down ${name:-$id}..."
            docker stop "$id" >/dev/null 2>&1 || true
            docker rm "$id"   >/dev/null 2>&1 || true
        done
    fi

    # Networks created for the project (plus the conventional name as a fallback).
    local -a nets=()
    mapfile -t nets < <(docker network ls --filter "label=com.docker.compose.project=${E2E_PROJECT}" --format '{{.Name}}' 2>/dev/null)
    docker network inspect "$E2E_NETWORK" >/dev/null 2>&1 && nets+=("$E2E_NETWORK")
    if [ "${#nets[@]}" -gt 0 ]; then
        found=1
        local net
        for net in $(printf '%s\n' "${nets[@]}" | sort -u); do
            log "Removing network ${net}..."
            docker network rm "$net" >/dev/null 2>&1 || true
        done
    fi

    # Ephemeral e2e volumes — safe to drop (containers are already gone above).
    local -a vols=()
    mapfile -t vols < <(docker volume ls -q --filter "label=com.docker.compose.project=${E2E_PROJECT}" 2>/dev/null)
    if [ "${#vols[@]}" -gt 0 ]; then
        found=1
        log "Removing volumes: ${vols[*]}"
        docker volume rm "${vols[@]}" >/dev/null 2>&1 || true
    fi

    # Leftover git-archive work dirs in the repo root.
    sweep_leftover_workdirs
    [ "$_SWEPT" -gt 0 ] && found=1

    if [ "$found" -eq 0 ]; then
        log "No leftover e2e artifacts found — nothing to do."
    else
        log "e2e teardown complete."
    fi
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

    # Stale e2e volumes (exist-e2e_*) are always safe to remove — they are ephemeral
    # artifacts from prior runs. If a previous run crashed before down -v completed,
    # the volume persists but its device path points to a deleted temp dir, causing
    # "exists but doesn't match config" on the next run.
    # NOTE: must be detected here but removed AFTER any stale containers are gone,
    # because docker volume rm fails if stopped containers still reference the volume.
    local stale_vols
    stale_vols=$(docker volume ls --filter "label=com.docker.compose.project=${E2E_PROJECT}" -q 2>/dev/null || true)

    _remove_stale_volumes() {
        if [ -n "$stale_vols" ]; then
            log "Removing stale e2e volumes: $(echo "$stale_vols" | tr '\n' ' ')"
            # shellcheck disable=SC2086
            docker volume rm $stale_vols 2>/dev/null || true
        fi
    }

    if [ "$errors" -eq 0 ]; then
        _remove_stale_volumes
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
        _remove_stale_volumes
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
    if [ -n "$WORK" ] && [ -d "$WORK" ]; then
        # Containers write files owned by their internal UIDs (not the host user).
        # Use a root container to remove those files before the host rm -rf.
        docker run --rm -u 0 -v "${WORK}:/cleanup" alpine \
            sh -c 'rm -rf /cleanup/*' 2>/dev/null || true
        rm -rf "$WORK" 2>/dev/null || true
    fi
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

    # 6. Bring services up. --build is mandatory: docker compose reuses cached
    #    images and never rebuilds on a Dockerfile change, so without it e2e can
    #    silently test a stale image of the committed code (this is exactly how a
    #    crash-looping decree daemon once slipped through as a PASS).
    log "Starting services..."
    docker compose -p "$E2E_PROJECT" -f "$WORK/docker-compose.yml" up -d --build

    # 7. Wait for containers to settle out of created/restarting transients.
    #    Best-effort — the container-health gate below is the actual verdict.
    wait_running "$WORK" || true

    # 8. Container-state gate — fails the quest if anything is restart-looping,
    #    exited, or unhealthy. This is the only place with docker visibility, so
    #    it's where daemon liveness (decree + sidecars, no HTTP surface) is checked.
    if ! bash "${REPO_DIR}/src/test/integration/container-health.sh" \
            "$WORK/docker-compose.yml" "$E2E_PROJECT"; then
        log "${quest_name} — container health gate FAILED"
        return 1
    fi

    # 9. Run per-service tests
    log "Running service tests for ${quest_name}:"
    local e2e_paths=""
    for var in $(quest_vars "$yaml"); do
        local svc_path; svc_path=$(var_to_path "$var")
        if [ -f "$WORK/${svc_path}/exist.test.sh" ]; then
            log "  • ${svc_path}/exist.test.sh"
            e2e_paths="${e2e_paths:+${e2e_paths}:}${svc_path}"
        fi
    done
    if ! docker compose -p "$E2E_PROJECT" -f "$WORK/existential-compose.yml" run --rm \
            -e E2E_MODE=1 \
            -e "E2E_SERVICE_PATHS=${e2e_paths}" \
            --entrypoint "" existential-adhoc \
            bash /src/test/run-all.sh; then
        log "${quest_name} — service tests FAILED"
        return 1
    fi

    log "${quest_name} — PASSED"
    cleanup
    return 0
}

# ── Main ──────────────────────────────────────────────────────────────────────

# `e2e down` — spin down leftover artifacts from a crashed run, then exit.
# Must come before the build/selection logic so it never starts anything.
if [ "${1:-}" = "down" ]; then
    e2e_down
    exit 0
fi

# Always start from a clean slate: a previous run that crashed before its trap
# fired can leave root-owned .tmp-e2e-* dirs behind (they accumulate otherwise).
sweep_leftover_workdirs

# Build adhoc image once — used for template rendering, compose gen, and tests.
log "Building existential-adhoc image..."
docker compose -p "$E2E_PROJECT" -f "${REPO_DIR}/existential-compose.yml" build existential-adhoc

# Quest selection
declare -a SELECTED_YAMLS=()

if [ "${1:-}" = "--all" ]; then
    # Explicitly run every automatable quest
    mapfile -t SELECTED_YAMLS < <(automatable_quests)
    [ "${#SELECTED_YAMLS[@]}" -gt 0 ] || die "No automatable quests found."
elif [ "$#" -gt 0 ]; then
    # Name patterns (e2e automation, e2e ai finance) select specific quests in
    # any context — checked before the TTY branches so it works non-interactively
    # too. Dedupe while preserving order (a pattern may match several quests).
    mapfile -t SELECTED_YAMLS < <(quests_by_names "$@" | awk '!seen[$0]++')
    [ "${#SELECTED_YAMLS[@]}" -gt 0 ] || die "No e2e-able quests matched: $*"
elif [ ! -t 0 ]; then
    # Non-interactive with no selection: run every automatable quest
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
