#!/usr/bin/env bash
# e2e.sh — end-to-end test harness.
#
# For each quest (1–6), creates a clean git-archive copy of the repo,
# enables the quest's services, renders templates, generates a unified
# docker-compose, brings it up, runs exist.test.sh for every enabled
# service inside the existential-adhoc container (which shares the
# same Docker network as the services), then tears everything down.
#
# Quests 7 (Network Access) and 8 (NAS Storage) are excluded — they
# require external infrastructure (DNS, TLS, TrueNAS) that can't be
# spun up in a self-contained environment.
#
# Usage (via existential.sh):
#   ./existential.sh e2e              # all quests 1–6
#   ./existential.sh e2e 3            # quest 3 only
#   ./existential.sh e2e 1 3 5        # specific quests
#
# Requirements:
#   - Docker + Docker Compose v2 on the host
#   - No conflicting containers already running (container_name values
#     are fixed — the pre-flight check catches this and tells you what to stop)

set -euo pipefail
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FIXTURES="${REPO_DIR}/src/test/fixtures"
E2E_PROJECT="exist-e2e"
E2E_NETWORK="${E2E_PROJECT}_exist"

# ── Quest service vars (mirrors quest.sh quest_vars()) ────────────────────────

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
    esac
}

# Maps EXIST_IS_* var → relative service path (mirrors quest.sh var_path())
var_to_path() {
    case "$1" in
        EXIST_IS_AI_CHATTERBOX)           echo "ai/chatterbox" ;;
        EXIST_IS_AI_HERMES)               echo "ai/hermes" ;;
        EXIST_IS_AI_LIGHTRAG)             echo "ai/lightrag" ;;
        EXIST_IS_AI_MCP)                  echo "ai/mcp" ;;
        EXIST_IS_AI_OLLAMA)               echo "ai/ollama" ;;
        EXIST_IS_AI_OPEN_WEBUI)           echo "ai/open-webui" ;;
        EXIST_IS_AI_WHISPER)              echo "ai/whisper" ;;
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
        EXIST_IS_HOSTING_PORTAINER)       echo "hosting/portainer" ;;
        EXIST_IS_HOSTING_GRAFANA)         echo "hosting/grafana" ;;
        EXIST_IS_HOSTING_PROMETHEUS)      echo "hosting/prometheus" ;;
        EXIST_IS_HOSTING_LOKI)            echo "hosting/loki" ;;
        EXIST_IS_HOSTING_UPTIME_KUMA)     echo "hosting/uptime-kuma" ;;
        EXIST_IS_SERVICES_DASHY)          echo "services/dashy" ;;
    esac
}

# ── Helpers ───────────────────────────────────────────────────────────────────

log()  { printf '\n[e2e] %s\n' "$*"; }
die()  { printf '\n[e2e] FATAL: %s\n' "$*" >&2; exit 1; }
hr()   { printf '[e2e] '; printf '%0.s─' {1..54}; echo; }

wait_running() {
    local work="$1" timeout="${2:-300}"
    local deadline=$(( $(date +%s) + timeout ))
    log "Waiting for containers (up to ${timeout}s)..."
    while [ "$(date +%s)" -lt "$deadline" ]; do
        local total running
        total=$(docker compose -p "$E2E_PROJECT" -f "$work/docker-compose.yml" \
                    ps -q 2>/dev/null | wc -l | tr -d ' ')
        running=$(docker compose -p "$E2E_PROJECT" -f "$work/docker-compose.yml" \
                    ps -q --status running 2>/dev/null | wc -l | tr -d ' ')
        [ "$total" -gt 0 ] && [ "$total" -eq "$running" ] && { echo; return 0; }
        printf '.'
        sleep 5
    done
    echo
    log "Timeout — current container state:"
    docker compose -p "$E2E_PROJECT" -f "$work/docker-compose.yml" ps || true
    return 1
}

# ── Pre-flight collision detection ────────────────────────────────────────────
#
# container_name values in this repo are fixed identifiers — if any matching
# container already exists (running or stopped), docker compose will refuse to
# start it and the test will fail in a confusing way. Check first.

preflight_check() {
    local quests="$1"
    local errors=0

    # Collect every container_name from compose files for the quests being tested
    declare -a wanted=()
    for quest in $quests; do
        for var in $(quest_vars "$quest"); do
            local path
            path=$(var_to_path "$var") || continue
            local compose="${REPO_DIR}/${path}/docker-compose.exist.yml"
            [ -f "$compose" ] || continue
            while IFS= read -r name; do
                [[ -n "$name" ]] && wanted+=("$name")
            done < <(grep -E '^\s+container_name:' "$compose" 2>/dev/null | awk '{print $NF}')
        done
    done

    # Also check for the existential-adhoc container itself
    wanted+=("existential-adhoc")

    # Snapshot of all existing containers (any state)
    local existing
    existing=$(docker ps -a --format '{{.Names}}' 2>/dev/null || true)

    declare -a collisions=()
    for name in "${wanted[@]}"; do
        if echo "$existing" | grep -qxF "$name"; then
            local state
            state=$(docker inspect --format '{{.State.Status}}' "$name" 2>/dev/null || echo "unknown")
            collisions+=("${name} (${state})")
            errors=$(( errors + 1 ))
        fi
    done

    # Check for a leftover e2e network from a previous failed run
    local stale_network=0
    if docker network inspect "$E2E_NETWORK" >/dev/null 2>&1; then
        stale_network=1
        errors=$(( errors + 1 ))
    fi

    if [ "$errors" -eq 0 ]; then
        log "Pre-flight OK"
        return 0
    fi

    echo ""
    echo "[e2e] ✗ PRE-FLIGHT FAILED — the following must be resolved before running e2e tests."
    echo ""

    if [ "${#collisions[@]}" -gt 0 ]; then
        echo "[e2e]   Conflicting containers (already exist on this host):"
        for c in "${collisions[@]}"; do
            echo "[e2e]     $c"
        done
        echo ""
        echo "[e2e]   These container_name values are fixed in the compose files — Docker"
        echo "[e2e]   will refuse to create them if they already exist."
        echo ""
        echo "[e2e]   If your real stack is running:"
        echo "[e2e]     docker compose down"
        echo ""
        echo "[e2e]   To remove specific containers:"
        local names_only=()
        for c in "${collisions[@]}"; do names_only+=("${c% (*)}"); done
        echo "[e2e]     docker rm -f ${names_only[*]}"
        echo ""
        echo "[e2e]   To see everything currently running:"
        echo "[e2e]     docker ps -a --format 'table {{.Names}}\t{{.Status}}'"
    fi

    if [ "$stale_network" -eq 1 ]; then
        echo "[e2e]   Stale network '${E2E_NETWORK}' from a previous failed run:"
        echo "[e2e]     docker network rm ${E2E_NETWORK}"
        echo ""
    fi

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
    [ -n "$WORK" ] && [ -d "$WORK" ] && rm -rf "$WORK"
    WORK=""
}
trap cleanup EXIT INT TERM

run_quest() {
    local quest="$1"
    hr
    log "Quest ${quest} — start"
    hr

    WORK=$(mktemp -d "$REPO_DIR/.tmp-e2e-XXXXX")

    # 1. Fresh clone from git archive (tracked files only, no secrets)
    log "Creating fresh clone..."
    git -C "$REPO_DIR" archive HEAD | tar -x -C "$WORK"

    # 2. Pre-fill .env.shared from fixture (bypasses EXIST_CLI prompts)
    cp "$FIXTURES/env.shared" "$WORK/.env.shared"

    # 3. Enable this quest's services
    log "Enabling quest ${quest} services..."
    for var in $(quest_vars "$quest"); do
        sed -i "s|^${var}=false|${var}=true|" "$WORK/.env.shared"
    done

    # 4. Render service templates (non-interactive — .env.shared already present)
    log "Rendering templates..."
    (cd "$WORK" && bash existential.sh templates)

    # 5. Generate unified docker-compose.yml via the adhoc container
    log "Generating docker-compose.yml..."
    docker compose -p "$E2E_PROJECT" -f "$WORK/existential-compose.yml" run --rm \
        --entrypoint "" existential-adhoc \
        tsx /src/generate-compose.ts /repo

    [ -f "$WORK/docker-compose.yml" ] || die "generate-compose.ts produced no docker-compose.yml"

    # 6. Bring services up
    log "Starting services..."
    docker compose -p "$E2E_PROJECT" -f "$WORK/docker-compose.yml" up -d

    # 7. Wait for all containers to reach running state
    wait_running "$WORK" 300

    # 8. Run per-service tests inside the adhoc container (same network as services)
    log "Running service tests..."
    docker compose -p "$E2E_PROJECT" -f "$WORK/existential-compose.yml" run --rm \
        -e E2E_MODE=1 \
        --entrypoint "" existential-adhoc \
        bash /src/test/run-all.sh

    log "Quest ${quest} — PASSED"
    cleanup
}

# ── Main ──────────────────────────────────────────────────────────────────────

QUESTS="${*:-1 2 3 4 5 6}"

for q in $QUESTS; do
    [[ "$q" =~ ^[1-6]$ ]] || die "Quest ${q} is not e2e-testable (only quests 1–6)"
done

preflight_check "$QUESTS"

PASS=(); FAIL=()

for q in $QUESTS; do
    if run_quest "$q"; then
        PASS+=("$q")
    else
        FAIL+=("$q")
        log "Quest ${q} — FAILED"
        cleanup
    fi
done

hr
log "Results: ${#PASS[@]} passed, ${#FAIL[@]} failed"
[ "${#PASS[@]}" -gt 0 ] && log "  Passed: quests ${PASS[*]}"
[ "${#FAIL[@]}" -gt 0 ] && log "  Failed: quests ${FAIL[*]}"
hr

[ "${#FAIL[@]}" -eq 0 ]
