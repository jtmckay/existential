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
# Env:
#   EXIST_E2E_OLLAMA_URL    run against an ollama on another machine (see quest_requires)
#   EXIST_E2E_OLLAMA_MODEL  override the chat/extract/vision tag for that server
#   E2E_HEALTH_TIMEOUT      seconds to wait for healthchecks (default 300)
#   E2E_KEEP=1              skip teardown so a failure can be inspected
#
# Requirements:
#   - Docker + Docker Compose v2 on the host
#   - No conflicting containers already running (the pre-flight check catches this)

set -euo pipefail
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
FIXTURES="${REPO_DIR}/src/test/fixtures"
QUEST_DIR="${REPO_DIR}/src/quests"

# The vendor table, for the rules a vendor imposes on service enablement.
# shellcheck source=../../utils/gpu-vendor.sh
. "${REPO_DIR}/src/utils/gpu-vendor.sh"
E2E_PROJECT="exist-e2e"
E2E_NETWORK="${E2E_PROJECT}_exist"

# ── Quest helpers ─────────────────────────────────────────────────────────────

# List EXIST_IS_* vars for a quest YAML file.
# A quest is markdown: YAML frontmatter, then the guide. Everything read here
# is data, so scope it to the frontmatter — otherwise a guide that happens to
# show a `- var:` line in an example would be parsed as if it were config.
quest_fm() { awk 'NR==1 && /^---$/{f=1;next} f && /^---$/{exit} f' "$1"; }

quest_vars() {
    quest_fm "$1" | grep '^\s*- var:' | awk '{print $3}'
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

# Return all numbered quest files with e2e: true in their frontmatter.
automatable_quests() {
    for yaml in "${QUEST_DIR}"/[0-9][0-9]-*.md; do
        quest_fm "$yaml" | grep -q '^e2e:[[:space:]]*true' && echo "$yaml"
    done
}

# A quest may name an env var the RUNNER has to supply — something no fixture can
# fake because it is real infrastructure outside the clone:
#
#   e2e_requires: EXIST_E2E_OLLAMA_URL
#
# The point is Core. Core is only meaningful with a chat model behind it, and a
# CI box has no GPU — so instead of dropping the flagship path from e2e
# entirely, it runs against an ollama someone else is hosting. Set the var and
# Core is exercised for real; leave it unset and the quest skips with a reason
# rather than failing in a way that looks like a bug in the stack.
quest_requires() { quest_fm "$1" | grep '^e2e_requires:' | sed 's/^e2e_requires:[[:space:]]*//'; }

# 0 when every requirement is satisfied; otherwise 1, having said what is missing.
quest_requirements_met() {
    local yaml="$1" var missing=""
    for var in $(quest_requires "$yaml"); do
        [ -n "${!var:-}" ] || missing+="${var} "
    done
    [ -z "$missing" ] && return 0
    log "SKIP $(quest_name "$yaml") — needs: ${missing}"
    log "     e.g. ${missing%% *}=http://192.168.1.20:11434 ./existential.sh e2e ..."
    return 1
}

# Resolve name patterns (e.g. "automation" or "ai finance") to automatable
# quest file paths. Each pattern is matched case-insensitively against the
# quest's `name:` field and its filename. A pattern that matches only a
# non-e2e quest (one needing manual NAS/DNS/TLS setup) reports why it's
# skipped; a pattern that matches nothing is warned about. Output may contain
# duplicates — the caller dedupes while preserving order.
quest_name() { quest_fm "$1" | grep '^name:' | sed 's/^name:[[:space:]]*//'; }

quests_by_names() {
    local -a all=()
    mapfile -t all < <(automatable_quests)
    local pat yaml found hit
    for pat in "$@"; do
        found=""
        for yaml in "${all[@]}"; do
            if grep -qi -- "$pat" <<<"$(quest_name "$yaml")" \
            || grep -qi -- "$pat" <<<"$(basename "$yaml" .md)"; then
                echo "$yaml"; found=1
            fi
        done
        [ -n "$found" ] && continue
        # No e2e-able match — was it a non-e2e quest, or just a typo?
        hit=""
        for yaml in "${QUEST_DIR}"/[0-9][0-9]-*.md; do
            if grep -qi -- "$pat" <<<"$(quest_name "$yaml")" \
            || grep -qi -- "$pat" <<<"$(basename "$yaml" .md)"; then
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

# Containers that declare a healthcheck get their own, longer wait.
#
# wait_running above only clears the created/restarting transients; a container
# that is "running (health: starting)" satisfies it immediately. hermes boots a
# model gateway and open-webui builds its first-run database, and both are still
# starting long after that — so testing at the 30s mark reported them as product
# failures when the harness was simply impatient. Containers without a
# healthcheck cannot be waited on and are not counted.
#
# Best-effort, like wait_running: on timeout it says what is still starting and
# proceeds, because the service tests are the actual verdict.
wait_healthy() {
    local work="$1" timeout="${2:-${E2E_HEALTH_TIMEOUT:-300}}"
    local deadline=$(( $(date +%s) + timeout ))
    local starting
    log "Waiting for healthchecks to pass (up to ${timeout}s)..."
    while [ "$(date +%s)" -lt "$deadline" ]; do
        starting=$(docker compose -p "$E2E_PROJECT" -f "$work/docker-compose.yml" ps -q 2>/dev/null \
            | xargs -r docker inspect \
                --format '{{if .State.Health}}{{.State.Health.Status}}{{end}}' 2>/dev/null \
            | grep -c '^starting$' || true)
        if [ "${starting:-0}" -eq 0 ]; then
            echo
            return 0
        fi
        printf '.'
        sleep 5
    done
    echo
    log "Still starting after ${timeout}s — proceeding to tests:"
    docker compose -p "$E2E_PROJECT" -f "$work/docker-compose.yml" ps -q 2>/dev/null \
        | xargs -r docker inspect \
            --format '{{if .State.Health}}{{if eq .State.Health.Status "starting"}}  {{.Name}}{{end}}{{end}}' \
            2>/dev/null | grep . || true
    return 0
}

# The external ollama must actually serve the models the run will ask for.
#
# EXIST_E2E_OLLAMA_URL redirects the URL and nothing else, so a runner whose box
# serves different tags than .env.exist.shared's defaults gets a stack that comes
# up perfectly clean and then fails every model call — which reads as a product
# bug rather than the setup mismatch it is. Check once, up front, and name what
# is actually there. EXIST_E2E_OLLAMA_MODEL overrides the chat/extract/vision tag.
check_ollama_models() {
    local work="$1" tags served want key
    local -a missing=()

    tags=$(curl -fsS -m 15 "${EXIST_E2E_OLLAMA_URL%/}/api/tags" 2>/dev/null) \
        || die "Cannot reach ${EXIST_E2E_OLLAMA_URL}/api/tags — is that ollama up?"
    # ollama reports "name:latest" for an untagged pull; compare without it so a
    # config that says `bge-m3` matches a served `bge-m3:latest`.
    served=$(printf '%s' "$tags" | jq -r '.models[].name' | sed 's/:latest$//' | sort -u)

    for key in EXIST_MODEL_CHAT EXIST_MODEL_EXTRACT EXIST_MODEL_VISION EXIST_MODEL_EMBED; do
        want=$(grep -m1 "^${key}=" "$work/.env.shared" 2>/dev/null | cut -d= -f2-)
        [ -n "$want" ] || continue
        grep -qxF "${want%:latest}" <<<"$served" || missing+=("${key}=${want}")
    done

    if [ "${#missing[@]}" -gt 0 ]; then
        log "The external ollama does not serve every model this run needs:"
        printf '[e2e]   missing: %s\n' "${missing[@]}"
        log "  it serves: $(printf '%s' "$served" | tr '\n' ' ')"
        die "Pull the missing models, or set EXIST_E2E_OLLAMA_MODEL to one it has."
    fi
    log "Models OK on ${EXIST_E2E_OLLAMA_URL}: $(printf '%s' "$served" | tr '\n' ' ')"
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

# ── Flow tests ────────────────────────────────────────────────────────────────
#
# A per-service exist.test.sh can only see its own service. Everything the stack
# is actually FOR lives between services — a file lands in MinIO and an
# automation reacts to it — and that seam had no coverage at all: MinIO spent
# months posting bucket events to a port nothing served while every individual
# service test passed.
#
# A flow is a script in src/test/e2e/flows/ that declares which services it
# needs. Adding a flow is adding a file; nothing here enumerates them.
#
#   FLOW_NAME      one line, shown in the log
#   FLOW_REQUIRES  space-separated EXIST_IS_* vars, all of which must be on
#
# Both are read out of the source with grep rather than by sourcing the file,
# the same way minio-router reads PATTERN from a processor: a flow is a script
# to execute, not a library, and sourcing it would run it.
FLOW_DIR="${REPO_DIR}/src/test/e2e/flows"

flow_meta() {
    grep -m1 "^${2}=" "$1" | sed "s/^${2}=[\"']\(.*\)[\"']$/\1/"
}

run_flows() {
    local work="$1" quest_name="$2"
    [ -d "$FLOW_DIR" ] || return 0

    local ran=0 failed=0
    local flow name requires var missing
    for flow in "$FLOW_DIR"/*.sh; do
        [ -f "$flow" ] || continue
        name=$(flow_meta "$flow" FLOW_NAME)
        requires=$(flow_meta "$flow" FLOW_REQUIRES)

        missing=""
        for var in $requires; do
            grep -q "^${var}=true" "$work/.env.shared" || missing="${missing} ${var}"
        done
        if [ -n "$missing" ]; then
            log "  ↷ ${name:-$(basename "$flow")} — skipped (off:${missing})"
            continue
        fi

        log "  • ${name:-$(basename "$flow")}"
        if WORK="$work" E2E_PROJECT="$E2E_PROJECT" REPO_DIR="$REPO_DIR" bash "$flow"; then
            ran=$(( ran + 1 ))
        else
            log "  ✗ ${name:-$(basename "$flow")} — FAILED"
            failed=$(( failed + 1 ))
        fi
    done

    if [ "$failed" -gt 0 ]; then
        log "${quest_name} — ${failed} flow test(s) FAILED"
        return 1
    fi
    [ "$ran" -eq 0 ] && log "  (no flow tests apply to this quest)"
    return 0
}

# ── Per-quest runner ──────────────────────────────────────────────────────────

WORK=""

cleanup() {
    # E2E_KEEP=1 leaves the stack and its work dir standing. Teardown destroys
    # exactly the evidence a failure needs — the containers, their logs, and the
    # rendered clone — so a debugging run wants the opposite of the default.
    # `./existential.sh e2e down` reclaims everything afterwards.
    if [ "${E2E_KEEP:-}" = "1" ] && [ -n "$WORK" ]; then
        log "E2E_KEEP=1 — leaving the stack up for inspection."
        log "  containers:  docker compose -p ${E2E_PROJECT} -f ${WORK}/docker-compose.yml ps"
        log "  a log:       docker logs <container>"
        log "  clean up:    ./existential.sh e2e down"
        WORK=""
        return 0
    fi
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
# Signals raise an exit rather than running cleanup directly. A handler on
# INT/TERM returns to where it interrupted, so the old `trap cleanup EXIT INT
# TERM` tore the stack down and then let the run CONTINUE — against a $WORK it
# had just blanked. Every later step then resolved to "/docker-compose.yml" and
# "/existential-compose.yml", and the quest reported "FAILED" when the truth was
# that someone pressed Ctrl+C. Exiting instead fires the EXIT trap once, cleans
# up, and stops.
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

run_quest() {
    local yaml="$1"
    local quest_name; quest_name=$(quest_fm "$yaml" | grep '^name:' | sed 's/^name:[[:space:]]*//')

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
    # Run containers as the host user (the e2e host may not be 1000). existential.sh's
    # _ensure_host_ids does this for real runs; e2e renders directly, so inject here too
    # — otherwise the host-owned bind-mount dirs in $WORK wouldn't match the container uid.
    grep -q '^EXIST_PUID=' "$WORK/.env.shared" || printf 'EXIST_PUID=%s\n' "$(id -u)" >> "$WORK/.env.shared"
    grep -q '^EXIST_PGID=' "$WORK/.env.shared" || printf 'EXIST_PGID=%s\n' "$(id -g)" >> "$WORK/.env.shared"

    # 2b. An externally-hosted ollama, when the runner supplied one. This is the
    # `external` GPU vendor: no local ollama, no device reservation to satisfy,
    # and every model call goes to the other box. It is the only way a GPU-less
    # runner can exercise a quest whose whole point is the agent.
    if [ -n "${EXIST_E2E_OLLAMA_URL:-}" ]; then
        log "Using external ollama: ${EXIST_E2E_OLLAMA_URL}"
        _env_put() {
            if grep -q "^${1}=" "$WORK/.env.shared"; then
                sed -i "s|^${1}=.*|${1}=${2}|" "$WORK/.env.shared"
            else
                printf '%s=%s\n' "$1" "$2" >> "$WORK/.env.shared"
            fi
        }
        _env_put EXIST_GPU_VENDOR   external
        _env_put EXIST_OLLAMA_URL   "$EXIST_E2E_OLLAMA_URL"
        # Whatever `external` forbids, forbid here too. This used to be a
        # hardcoded EXIST_IS_AI_OLLAMA=false, which kept the harness correct
        # while real installs stayed broken -- the bug that fix was papering
        # over lived in quest.sh for months because e2e never saw it.
        while IFS= read -r _svc; do
            [ -n "$_svc" ] && _env_put "$_svc" false
        done < <(vendor_disabled_services external)
        # One tag covers chat, extract and vision — .env.exist.shared ships them
        # identical on purpose so a single resident model serves all three.
        if [ -n "${EXIST_E2E_OLLAMA_MODEL:-}" ]; then
            log "Using external model: ${EXIST_E2E_OLLAMA_MODEL}"
            _env_put EXIST_MODEL_CHAT    "$EXIST_E2E_OLLAMA_MODEL"
            _env_put EXIST_MODEL_EXTRACT "$EXIST_E2E_OLLAMA_MODEL"
            _env_put EXIST_MODEL_VISION  "$EXIST_E2E_OLLAMA_MODEL"
        fi
    fi

    # 3. Enable this quest's services
    log "Enabling services..."
    _vendor=$(grep -m1 '^EXIST_GPU_VENDOR=' "$WORK/.env.shared" | cut -d= -f2-)
    for var in $(quest_vars "$yaml"); do
        # The quest lists what it wants; the vendor answer outranks it. Same
        # rule quest.sh applies to a real install, from the same list.
        if [ -n "$_vendor" ] && vendor_forbids_service "$_vendor" "$var"; then
            log "  skipping ${var} — EXIST_GPU_VENDOR=${_vendor}"
            continue
        fi
        sed -i "s|^${var}=false|${var}=true|" "$WORK/.env.shared"
    done

    # 4. Render service templates (non-interactive — .env.shared already present)
    log "Rendering templates..."
    docker compose -p "$E2E_PROJECT" -f "$WORK/existential-compose.yml" run --rm \
        --user "$(id -u):$(id -g)" \
        --entrypoint "" \
        -e REPO_DIR=/repo \
        -e FORCE=false \
        existential-adhoc \
        bash /src/templates.sh

    # 4a. Models, before anything tries to use one. Runs after the render because
    #     that is when .env.shared has every model key — the fixture ships none of
    #     them, and templates.sh fills them from .env.exist.shared.
    if [ -n "${EXIST_E2E_OLLAMA_URL:-}" ]; then
        check_ollama_models "$WORK"
    fi

    # 4b. Pre-startup filesystem work, exactly as a real install gets it.
    #     ./existential.sh runs render → exist.initial.sh → up; skipping the
    #     middle step meant caddy could never start under e2e, because its
    #     internal.pem is minted here and the Caddyfile hard-references it.
    #     Sourcing existential.sh gives us the real run_initials rather than a
    #     second copy that could drift from it — and because BASH_SOURCE points
    #     at the clone, its SCRIPT_DIR is $WORK and every helper reads the
    #     clone's .env.shared. Runs in a subshell so its set -e and its
    #     SCRIPT_DIR stay out of this one.
    log "Running exist.initial.sh for enabled services..."
    (
        # shellcheck source=../../../existential.sh
        . "$WORK/existential.sh"
        run_initials
    ) || die "exist.initial.sh failed for one or more services — see above"

    # 5. Generate unified docker-compose.yml
    # Pass $WORK as the host-side repo root so generate-compose.ts can write
    # absolute bind-mount paths that resolve correctly when docker compose up
    # runs on the host (not inside the adhoc container).
    log "Generating docker-compose.yml..."
    docker compose -p "$E2E_PROJECT" -f "$WORK/existential-compose.yml" run --rm \
        --user "$(id -u):$(id -g)" \
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
    wait_healthy "$WORK" || true

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
            --user "$(id -u):$(id -g)" \
            -e E2E_MODE=1 \
            -e "E2E_SERVICE_PATHS=${e2e_paths}" \
            --entrypoint "" existential-adhoc \
            bash /src/test/run-all.sh; then
        log "${quest_name} — service tests FAILED"
        return 1
    fi

    # 10. Cross-service flow tests. Runs last: every flow assumes a stack whose
    #     individual services already pass, so a failure here is unambiguously
    #     about the wiring between them.
    log "Running flow tests for ${quest_name}:"
    if ! run_flows "$WORK" "$quest_name"; then
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
    for _y in "${QUEST_DIR}"/[0-9][0-9]-*.md; do
        quest_fm "$_y" | grep -q '^e2e:[[:space:]]*false' || continue
        _n=$(quest_name "$_y")
        _excl_header+=$'\n'"  ✗ ${_n}"
    done
    _excl_header+=$'\n─────────────────────────────────────────────────────\nSpace/Tab to toggle  ·  Enter to confirm'
    mapfile -t SELECTED_YAMLS < <(
        automatable_quests | while IFS= read -r _y; do
            _n=$(quest_name "$_y")
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
        _n=$(quest_name "${_all[$_i]}")
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
    name=$(quest_name "$yaml")
    log "  • ${name}"
done

# Filter on runner-supplied requirements BEFORE preflight. preflight demands the
# container names be free, which is a real requirement for a quest that is going
# to run — and pure noise for one that is about to skip. Asking someone to tear
# down their stack to be told "skipped" is the wrong order.
declare -a PASS=() FAIL=() SKIP=() RUNNABLE=()

for yaml in "${SELECTED_YAMLS[@]}"; do
    if quest_requirements_met "$yaml"; then
        RUNNABLE+=("$yaml")
    else
        SKIP+=("$(quest_name "$yaml")")
    fi
done

if [ "${#RUNNABLE[@]}" -eq 0 ]; then
    hr
    log "Results: 0 passed, 0 failed, ${#SKIP[@]} skipped"
    log "  Skipped: ${SKIP[*]}"
    exit 0
fi

preflight_check "${RUNNABLE[@]}"

for yaml in "${RUNNABLE[@]}"; do
    name=$(quest_name "$yaml")
    if run_quest "$yaml"; then
        PASS+=("$name")
    else
        FAIL+=("$name")
        log "${name} — FAILED"
        cleanup
    fi
done

hr
log "Results: ${#PASS[@]} passed, ${#FAIL[@]} failed, ${#SKIP[@]} skipped"
[ "${#PASS[@]}" -gt 0 ] && log "  Passed:  ${PASS[*]}"
[ "${#FAIL[@]}" -gt 0 ] && log "  Failed:  ${FAIL[*]}"
[ "${#SKIP[@]}" -gt 0 ] && log "  Skipped: ${SKIP[*]}"
hr

[ "${#FAIL[@]}" -eq 0 ]
