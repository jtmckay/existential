#!/usr/bin/env bash
# e2e.sh — end-to-end test harness.
#
# For each selected quest: make a clean git-archive copy of the repo, enable the
# quest's services, render templates, generate a unified docker-compose, bring it
# up, then drop this run's CHECKS into the decree inbox and let the daemon run
# them. Every check writes runs/<id>/{message.md,routine.log,run.json}; that
# evidence is copied to e2e-out/ before the stack is torn down.
#
# A check is a markdown file in checks/ — see checks/README.md. Adding a check is
# adding a file; nothing here enumerates them.
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
#   E2E_HEALTH_TIMEOUT   seconds to wait for healthchecks (default 300)
#   E2E_CHECK_TIMEOUT    seconds to wait for the checks to drain (default 900)
#   E2E_KEEP=1           skip teardown so a failure can be inspected live
#   E2E_OUT              output directory (default <repo>/e2e-out)
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

# Evidence collection, kept sourceable so harness-selftest.sh can drive it
# against a fabricated runs/ tree without spinning up a stack.
# shellcheck source=results.sh
. "${REPO_DIR}/src/test/e2e/results.sh"

CHECK_DIR="${REPO_DIR}/src/test/e2e/checks"
E2E_OUT="${E2E_OUT:-${REPO_DIR}/e2e-out}"
E2E_PROJECT="exist-e2e"
E2E_NETWORK="${E2E_PROJECT}_exist"

# ── Quest helpers ─────────────────────────────────────────────────────────────

# A quest is markdown: YAML frontmatter, then the guide. Everything read here
# is data, so scope it to the frontmatter — otherwise a guide that happens to
# show a `- var:` line in an example would be parsed as if it were config.
# Single keys go through e2e_fm_get (results.sh); this is for the one consumer
# that needs the whole block, because `services:` is a list, not a key.
quest_fm() { awk 'NR==1 && /^---$/{f=1;next} f && /^---$/{exit} f' "$1"; }

# List EXIST_IS_* vars for a quest.
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
        [ "$(e2e_fm_get "$yaml" e2e)" = true ] && echo "$yaml"
    done
}

quest_name() { e2e_fm_get "$1" name; }

# Resolve name patterns (e.g. "automation" or "ai finance") to automatable
# quest file paths. Each pattern is matched case-insensitively against the
# quest's `name:` field and its filename. A pattern that selects nothing —
# a typo, or a quest that isn't e2e-able — is warned about and skipped.
# Output may contain duplicates — the caller dedupes while preserving order.
quests_by_names() {
    local -a all=()
    mapfile -t all < <(automatable_quests)
    local pat yaml found
    for pat in "$@"; do
        found=""
        for yaml in "${all[@]}"; do
            if grep -qi -- "$pat" <<<"$(quest_name "$yaml")" \
            || grep -qi -- "$pat" <<<"$(basename "$yaml" .md)"; then
                echo "$yaml"; found=1
            fi
        done
        [ -n "$found" ] || log "No quest matched '${pat}' — skipped" >&2
    done
}

# ── Helpers ───────────────────────────────────────────────────────────────────

log()  { printf '\n[e2e] %s\n' "$*"; }
# Every compose call against the e2e stack goes through here — the -p/-f pair was
# repeated a dozen times, and each copy was a chance to address the wrong stack.
_compose() { local w="$1"; shift; docker compose -p "$E2E_PROJECT" -f "$w/docker-compose.yml" "$@"; }
die()  { printf '\n[e2e] FATAL: %s\n' "$*" >&2; exit 1; }
hr()   { printf '[e2e] '; printf '%0.s─' {1..54}; echo; }

# Wait for the stack to settle: no created/restarting transients, and nothing
# still "health: starting".
#
# This was two functions with two budgets. The first cleared the transients in
# 30s and considered a container "running (health: starting)" settled — which
# hermes and open-webui are for minutes while a model gateway boots and a
# first-run database builds, so tests fired early and reported the harness's
# impatience as product failures. Both were called with `|| true` and neither
# was ever the verdict: container-health.sh is, and it resamples and applies its
# own flap threshold. So one wait, one generous budget, still best-effort.
wait_settled() {
    local work="$1" timeout="${2:-${E2E_HEALTH_TIMEOUT:-300}}"
    local deadline=$(( $(date +%s) + timeout ))
    local unsettled
    log "Waiting for containers to settle (up to ${timeout}s)..."
    while [ "$(date +%s)" -lt "$deadline" ]; do
        unsettled=$(_compose "$work" ps -q --status created --status restarting 2>/dev/null | wc -l | tr -d ' ')
        unsettled=$(( unsettled + $(_compose "$work" ps -q 2>/dev/null \
            | xargs -r docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{end}}' 2>/dev/null \
            | grep -c '^starting$' || true) ))
        [ "$unsettled" -eq 0 ] && { echo; return 0; }
        printf '.'
        sleep 5
    done
    echo
    log "Still unsettled after ${timeout}s — proceeding; the health gate is the verdict:"
    _compose "$work" ps || true
    return 0
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
#
# Anything labelled with our own compose project is ours and is always safe to
# remove — that is e2e_down's whole job, so preflight calls it rather than
# carrying a second copy of the sweep. What is left over after that can only be
# a collision with the user's REAL stack, which is the one case worth stopping
# and asking about.

preflight_check() {
    local -a yaml_files=("$@")

    # Reclaim our own leftovers first. Doing this before looking for collisions
    # also removes the ordering hazard the old inline version had to document:
    # a stale volume cannot be removed while a stopped container still
    # references it, and e2e_down takes them down in that order already.
    e2e_down >/dev/null 2>&1 || true

    # Every container_name the selected quests would claim.
    local -a wanted=("existential-adhoc")
    local yaml var path compose name
    for yaml in "${yaml_files[@]}"; do
        for var in $(quest_vars "$yaml"); do
            path=$(var_to_path "$var")
            compose="${REPO_DIR}/${path}/docker-compose.exist.yml"
            [ -f "$compose" ] || continue
            while IFS= read -r name; do
                [ -n "$name" ] && wanted+=("$name")
            done < <(grep -E '^\s+container_name:' "$compose" 2>/dev/null | awk '{print $NF}')
        done
    done

    local existing
    existing=$(docker ps -a --format '{{.Names}}' 2>/dev/null || true)

    local -a collisions=() names_only=()
    for name in "${wanted[@]}"; do
        if grep -qxF "$name" <<<"$existing"; then
            collisions+=("${name} ($(docker inspect --format '{{.State.Status}}' "$name" 2>/dev/null || echo unknown))")
            names_only+=("$name")
        fi
    done

    if [ "${#collisions[@]}" -eq 0 ]; then
        log "Pre-flight OK"
        return 0
    fi

    echo ""
    echo "[e2e] ✗ PRE-FLIGHT FAILED — these container names are already taken:"
    printf '[e2e]     %s\n' "${collisions[@]}"
    echo ""
    echo "[e2e]   If these are your real stack, stop it first:  docker compose down"
    echo ""

    if [ -t 0 ]; then
        echo "[e2e]   Press Enter to remove them and continue (Ctrl-C to abort)."
        echo "[e2e]   Note: only containers are removed — named and NFS volumes are untouched."
        printf '[e2e] > '
        read -r _
        docker rm -f "${names_only[@]}" >/dev/null
        log "Pre-flight OK (cleaned up)"
        return 0
    fi

    echo "[e2e]   To remove:  docker rm -f ${names_only[*]}"
    return 1
}

# ── Checks ────────────────────────────────────────────────────────────────────
#
# A check is a decree message in checks/ (see checks/README.md). e2e stages any
# sibling routine into the clone, drops the applicable messages into the inbox,
# and lets the daemon run them — one per run dir, each with its own verdict, and
# one failure never hiding the rest.
#
# Frontmatter is read with e2e_fm_get (results.sh) rather than by sourcing or by
# a YAML parser: a check is data e2e reads and data decree reads, and the two
# must not disagree about what the file says.

# Checks whose `requires:` vars are all enabled in the clone.
applicable_checks() {
    local work="$1" md name var missing
    for md in "$CHECK_DIR"/[0-9][0-9]-*.md; do
        [ -f "$md" ] || continue
        name="$(basename "$md" .md)"
        missing=""
        for var in $(e2e_fm_get "$md" requires); do
            grep -q "^${var}=true" "$work/.env.shared" || missing="${missing} ${var}"
        done
        if [ -n "$missing" ]; then
            log "  ↷ ${name} — skipped (off:${missing})" >&2
            continue
        fi
        echo "$md"
    done
}

# Stage checks into the clone, BEFORE render and up. Everything here is read
# once at container start, which is precisely why it cannot be done from inside
# a check: the daemon is already running by then.
#
#   - sibling routines land in shared_routines/ and are registered enabled
#   - each check's needs_routines are switched on
#   - max_attempts drops to 1: decree retries three times by default, which for
#     a failing check means three times the wall clock and three routine-N.log
#     files to read. The clone only; a real install still gets its retries.
stage_checks() {
    local work="$1" md name sh cfg
    cfg="$work/services/decree/decree/config.exist.yml"
    [ -f "$cfg" ] || { log "  (no decree in this quest — no checks to stage)"; return 0; }

    sed -i 's/^max_attempts:.*/max_attempts: 1/' "$cfg"

    local -a enable=()
    for md in "$CHECK_DIR"/[0-9][0-9]-*.md; do
        [ -f "$md" ] || continue
        name="$(basename "$md" .md)"
        sh="${md%.md}.sh"
        if [ -f "$sh" ]; then
            cp "$sh" "$work/automations/shared_routines/$(e2e_fm_get "$md" routine).sh"
            enable+=("$(e2e_fm_get "$md" routine)")
        fi
        # needs_routines is a space-separated list, so splitting is the point.
        local -a needs=()
        read -r -a needs <<<"$(e2e_fm_get "$md" needs_routines)"
        enable+=("${needs[@]+"${needs[@]}"}")
    done

    local r
    for r in $(printf '%s\n' "${enable[@]+"${enable[@]}"}" | awk 'NF && !seen[$0]++'); do
        if grep -q "^  ${r}:$" "$cfg"; then
            # Flip this routine's own enabled:, and only this one.
            awk -v r="$r" '
                $0 == "  " r ":" { print; inblock = 1; next }
                inblock && /^ *enabled:/ { sub(/false/, "true"); inblock = 0 }
                { print }
            ' "$cfg" > "${cfg}.tmp" && mv "${cfg}.tmp" "$cfg"
        else
            printf '  %s:\n    enabled: true\n' "$r" >> "$cfg"
        fi
        grep -A1 "^  ${r}:$" "$cfg" | grep -q 'enabled: true' \
            || die "could not enable decree routine ${r}"
    done
    [ "${#enable[@]}" -gt 0 ] && log "  staged routines: $(printf '%s\n' "${enable[@]}" | awk 'NF && !seen[$0]++' | tr '\n' ' ')"

    # A check may also carry a sibling <name>.stage.sh — host-side setup that has
    # to happen before the stack boots, for config a running container has
    # already read. It gets $WORK and nothing else; anything it can do at routine
    # runtime belongs in the routine instead, where the credentials exist.
    # The harness has no business knowing which services a check touches.
    local st
    for md in "$CHECK_DIR"/[0-9][0-9]-*.md; do
        st="${md%.md}.stage.sh"
        [ -f "$st" ] || continue
        WORK="$work" REPO_DIR="$REPO_DIR" bash "$st" \
            || die "$(basename "$st") failed — see above"
    done
    return 0
}

# Drop the applicable checks into the inbox. Filenames are prefixed so they sort
# after anything decree put there itself.
drop_checks() {
    local work="$1" md n=0
    local inbox="$work/services/decree/decree/inbox"
    [ -d "$inbox" ] || { log "  (no decree inbox — skipping checks)"; return 1; }

    # Wait for the daemon phase before dropping anything. decree's entrypoint
    # runs `decree process` first, and that drains the WHOLE inbox — so a check
    # landing during it is run by the migration pass, where the first dead letter
    # aborts the rest. Messages, not migrations, is the entire point; do not let
    # them be processed as migrations by accident. pid1 is `bash` through the
    # health-wait and migrations, and `decree` once the daemon is up, which is the
    # same signal the image's own healthcheck uses.
    local deadline=$(( $(date +%s) + 600 ))
    until docker exec decree grep -q decree /proc/1/comm 2>/dev/null; do
        if [ "$(date +%s)" -ge "$deadline" ]; then
            log "  decree never reached its daemon phase — nothing can run the checks"
            return 1
        fi
        sleep 5
    done

    while IFS= read -r md; do
        [ -n "$md" ] || continue
        cp "$md" "${inbox}/e2e-$(basename "$md")"
        log "  → $(basename "$md" .md)"
        n=$(( n + 1 ))
    done < <(applicable_checks "$work")
    [ "$n" -gt 0 ] || { log "  (no checks apply to this quest)"; return 1; }
    return 0
}

# Wait for the daemon to drain. Done when the inbox holds no *.md and no run is
# in flight; a dead letter does NOT end the wait, because the daemon carries on
# past one and the remaining checks still have results to produce.
#
# This also asserts the property that used to be the MinIO flow's last two
# steps, and it belongs here rather than there: a message that runs but never
# gets its run.json comes back on every tick forever, and nothing scoped to one
# check can see that. Nothing may be left stuck, from any routine.
await_checks() {
    local work="$1" timeout="${E2E_CHECK_TIMEOUT:-900}"
    local inbox="$work/services/decree/decree/inbox"
    local deadline=$(( $(date +%s) + timeout )) left
    log "Waiting for checks to drain (up to ${timeout}s)..."
    while [ "$(date +%s)" -lt "$deadline" ]; do
        left=$(find "$inbox" -maxdepth 1 -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
        [ "$left" -eq 0 ] && { echo; return 0; }
        printf '.'
        sleep 5
    done
    echo
    log "Inbox did not drain within ${timeout}s — still queued:"
    find "$inbox" -maxdepth 1 -name '*.md' -printf '[e2e]   %f\n' 2>/dev/null || true
    return 1
}

# Container logs for anything the health gate is unhappy about. Kept apart from
# collect_results so that stays pure-filesystem and testable without Docker.
collect_logs() {
    local work="$1" out="$2" id name state
    mkdir -p "$out/logs"
    while IFS= read -r id; do
        [ -n "$id" ] || continue
        state=$(docker inspect --format '{{.State.Status}}{{if .State.Health}} {{.State.Health.Status}}{{end}}' "$id" 2>/dev/null || true)
        case "$state" in
            "running"|"running healthy") continue ;;
        esac
        name=$(docker inspect --format '{{.Name}}' "$id" 2>/dev/null | sed 's#^/##')
        docker logs --tail 200 "$id" > "$out/logs/${name:-$id}.log" 2>&1 || true
    done < <(_compose "$work" ps -q 2>/dev/null)
    rmdir "$out/logs" 2>/dev/null || true
}

# Copy this quest's evidence out of the doomed clone and grade it. Returns
# non-zero when any check failed, so run_quest can fail the quest on it.
#
# This is what makes the harness inspectable at all. The clone is deleted on the
# way out, so for a long time the only way to see WHY something failed was to
# print it first — hence the flow test's inline stderr dump — or to skip teardown
# with E2E_KEEP=1 and go spelunking in containers. The evidence was always there
# in a good shape; it was just being thrown away.
collect_quest_results() {
    local work="$1" quest="$2" out slug rc=0
    slug="$(printf '%s' "$quest" | tr '[:upper:] ' '[:lower:]-' | tr -cd 'a-z0-9-')"
    out="${E2E_OUT}/$(date '+%Y-%m-%d_%H-%M-%S')-${slug}"

    collect_results "$work/automations/runs" \
                    "$work/services/decree/decree/inbox/dead" \
                    "$out" || rc=1
    collect_logs "$work" "$out"

    # Anything still queued is a stuck message: it will come back on every tick
    # forever. await_checks already failed the run for it — this only carries the
    # messages out as evidence, and it lives here rather than there because the
    # cleanup trap reaches this function on paths where await_checks never ran.
    local stuck
    stuck=$(find "$work/services/decree/decree/inbox" -maxdepth 1 -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
    if [ "${stuck:-0}" -gt 0 ]; then
        mkdir -p "$out/stuck"
        find "$work/services/decree/decree/inbox" -maxdepth 1 -name '*.md' \
            -exec cp {} "$out/stuck/" \; 2>/dev/null || true
        log "  ${stuck} message(s) left stuck in the inbox — see ${out#"${REPO_DIR}/"}/stuck/"
    fi

    log "Results → ${out#"${REPO_DIR}/"}/results.md"
    sed -n '/^|/p' "$out/results.md" 2>/dev/null | sed 's/^/[e2e]   /' || true
    return "$rc"
}

# ── Per-quest runner ──────────────────────────────────────────────────────────

WORK=""
QUEST_LABEL=""
COLLECTED=0

cleanup() {
    # Collect before anything is destroyed, if the run did not get that far
    # itself — a crash, a failed `up`, or a Ctrl+C. This is the case that most
    # needs the evidence, so it is the last thing that should go without it.
    if [ "$COLLECTED" -eq 0 ] && [ -n "$WORK" ] && [ -d "$WORK/automations/runs" ]; then
        collect_quest_results "$WORK" "${QUEST_LABEL:-interrupted}" || true
        COLLECTED=1
    fi

    # E2E_KEEP=1 leaves the stack and its work dir standing. Teardown destroys
    # exactly the evidence a failure needs — the containers, their logs, and the
    # rendered clone — so a debugging run wants the opposite of the default.
    # `./existential.sh e2e down` reclaims everything afterwards.
    if [ "${E2E_KEEP:-}" = "1" ] && [ -n "$WORK" ]; then
        log "E2E_KEEP=1 — leaving the stack up for inspection."
        log "  containers:  docker compose -p ${E2E_PROJECT} -f ${WORK}/docker-compose.yml ps"
        log "  a log:       docker logs <container>"
        log "  clean up:    ./existential.sh e2e down"
        log "  (the run's own evidence is already in ${E2E_OUT#"${REPO_DIR}/"}/ either way)"
        WORK=""
        return 0
    fi
    if [ -n "$WORK" ] && [ -f "$WORK/docker-compose.yml" ]; then
        log "Tearing down..."
        _compose "$WORK" down -v --remove-orphans 2>/dev/null || true
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
    local quest_name; quest_name=$(quest_name "$yaml")

    hr
    log "${quest_name} — start"
    hr

    QUEST_LABEL="$quest_name"
    COLLECTED=0
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

    # 3. Enable this quest's services.
    #
    # Plus decree, unconditionally: it is where the checks RUN, the same way
    # existential-adhoc is brought up for every quest whether or not the quest
    # asks for it. Four e2e-able quests (local-ai-lab, home-finance,
    # media-and-files, productivity-and-tools) do not list it, and without this
    # they would render a stack with nothing able to test it — which reads as a
    # pass while verifying nothing.
    sed -i 's|^EXIST_IS_SERVICES_DECREE=false|EXIST_IS_SERVICES_DECREE=true|' "$WORK/.env.shared"

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

    # 3b. Stage this run's checks into the clone. Before the render, because
    #     what it touches (decree's routine whitelist, the webhook route table,
    #     the probe processor) is read once at container start.
    log "Staging checks..."
    stage_checks "$WORK"

    # 4. Render service templates (non-interactive — .env.shared already present)
    log "Rendering templates..."
    docker compose -p "$E2E_PROJECT" -f "$WORK/existential-compose.yml" run --rm \
        --user "$(id -u):$(id -g)" \
        --entrypoint "" \
        -e REPO_DIR=/repo \
        -e FORCE=false \
        existential-adhoc \
        bash /src/templates.sh

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
    _compose "$WORK" up -d --build

    # 7. Wait for the stack to settle. Best-effort — the gate below is the verdict.
    wait_settled "$WORK" || true

    # 8. Container-state gate — fails the quest if anything is restart-looping,
    #    exited, or unhealthy. This is the only place with docker visibility, so
    #    it's where daemon liveness (decree, decree-backup — no HTTP surface) is checked.
    local health_rc=0
    bash "${REPO_DIR}/src/test/integration/container-health.sh" \
        "$WORK/docker-compose.yml" "$E2E_PROJECT" || health_rc=1
    [ "$health_rc" -eq 0 ] || log "${quest_name} — container health gate FAILED"

    # 9. The checks. Everything the quest actually verifies happens here: the
    #    per-service tests (00-services runs triage, which runs every enabled
    #    service's exist.test.sh) and each cross-service chain, as one message
    #    apiece. The health gate's result does not skip them — a quest with one
    #    unhealthy container still has results worth collecting for the rest.
    log "Running checks for ${quest_name}:"
    local checks_rc=0
    drop_checks "$WORK" || checks_rc=1
    [ "$checks_rc" -eq 0 ] && { await_checks "$WORK" || checks_rc=1; }

    # 10. Copy the evidence out before teardown destroys it, and grade it.
    collect_quest_results "$WORK" "$quest_name" || checks_rc=1
    COLLECTED=1

    if [ "$health_rc" -ne 0 ] || [ "$checks_rc" -ne 0 ]; then
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

# Build adhoc image once — used for template rendering, compose gen, and tests.
log "Building existential-adhoc image..."
docker compose -p "$E2E_PROJECT" -f "${REPO_DIR}/existential-compose.yml" build existential-adhoc

# Quest selection
declare -a SELECTED_YAMLS=()

if [ "${1:-}" = "--all" ] || { [ "$#" -eq 0 ] && [ ! -t 0 ]; }; then
    # Every automatable quest — asked for with --all, or implied by having no
    # selection and no terminal to ask on.
    mapfile -t SELECTED_YAMLS < <(automatable_quests)
    [ "${#SELECTED_YAMLS[@]}" -gt 0 ] || die "No automatable quests found."
elif [ "$#" -gt 0 ]; then
    # Name patterns (e2e automation, e2e ai finance) select specific quests in
    # any context — checked before the TTY branches so it works non-interactively
    # too. Dedupe while preserving order (a pattern may match several quests).
    mapfile -t SELECTED_YAMLS < <(quests_by_names "$@" | awk '!seen[$0]++')
    [ "${#SELECTED_YAMLS[@]}" -gt 0 ] || die "No e2e-able quests matched: $*"
else
    command -v fzf >/dev/null 2>&1 || die "fzf not found"
    # fzf on host — draw picker directly (fzf uses /dev/tty for UI, safe in <(...))
    _excl_header="Excluded (require manual setup):"
    for _y in "${QUEST_DIR}"/[0-9][0-9]-*.md; do
        [ "$(e2e_fm_get "$_y" e2e)" = false ] || continue
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
fi

log "Selected quests:"
for yaml in "${SELECTED_YAMLS[@]}"; do
    name=$(quest_name "$yaml")
    log "  • ${name}"
done

declare -a PASS=() FAIL=()

preflight_check "${SELECTED_YAMLS[@]}"

for yaml in "${SELECTED_YAMLS[@]}"; do
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
log "Results: ${#PASS[@]} passed, ${#FAIL[@]} failed"
log "  Evidence: ${E2E_OUT#"${REPO_DIR}/"}/"
[ "${#PASS[@]}" -gt 0 ] && log "  Passed:  ${PASS[*]}"
[ "${#FAIL[@]}" -gt 0 ] && log "  Failed:  ${FAIL[*]}"
hr

[ "${#FAIL[@]}" -eq 0 ]
