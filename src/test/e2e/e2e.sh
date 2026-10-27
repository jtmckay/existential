#!/usr/bin/env bash
# e2e.sh — does a FRESH INSTALL come up working?
#
# That question is the whole remit, and it is the one nothing else in this repo
# answers: `triage` already runs every enabled service's exist.test.sh on the
# real stack every five minutes, so per-service health needs no second home
# here. What triage cannot see is a first install — templates rendering,
# migrations running, one service reaching another for the first time.
#
# Per unit, Core and then each flow marked `e2e: true`: copy the WORKING TREE
# into a throwaway clone (tracked files plus untracked-but-not-ignored ones, so
# uncommitted work is what gets tested and secrets stay out by git's own ignore
# rules), turn the flow on (its services, the flows it needs, its files),
# render, up, then drop this run's CHECKS into the
# decree inbox once the stack is healthy and let the daemon run them. Evidence
# lands in e2e-out/ before teardown.
#
# A check is a markdown file in checks/ — a decree message, run after the stack
# is up because that is when "does it work?" can be asked. Adding a check is
# adding a file; nothing here enumerates them.
#
# Usage (via existential.sh):
#   ./existential.sh e2e                 # Core, then every e2e flow
#   ./existential.sh e2e core search     # units matching a name pattern
#   ./existential.sh e2e down            # reclaim artifacts from a crashed run
#
# Env:
#   E2E_HEALTH_TIMEOUT   seconds to wait for healthchecks (default 300)
#   E2E_CHECK_TIMEOUT    seconds to wait for decree to finish migrating (default 900)
#   E2E_KEEP=1           skip teardown so a failure can be inspected live
#   E2E_OUT              output directory (default <repo>/e2e-out)

set -euo pipefail
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
FIXTURES="${REPO_DIR}/src/test/fixtures"

# shellcheck source=../../utils/flows.sh
. "${REPO_DIR}/src/utils/flows.sh"
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

log()  { printf '\n[e2e] %s\n' "$*"; }
die()  { printf '\n[e2e] FATAL: %s\n' "$*" >&2; exit 1; }
hr()   { printf '[e2e] '; printf '%0.s─' {1..54}; echo; }
# Every compose call against the e2e stack goes through here — each open-coded
# -p/-f pair was a chance to address the wrong stack.
_compose() { local w="$1"; shift; docker compose -p "$E2E_PROJECT" -f "$w/docker-compose.yml" "$@"; }

# ── Units ─────────────────────────────────────────────────────────────────────
# "core" is the install as it ships; every other unit is a flow marked e2e: true,
# turned on over Core the way `./existential.sh flow on` does it. The rest need
# external infrastructure (a Gmail grant, a NAS, model checkpoints).

unit_name() { if [ "$1" = core ]; then echo Core; else flow_get "$1" name; fi; }
units() {
    local n
    echo core
    for n in $(flow_names); do [ "$(flow_get "$n" e2e)" = true ] && echo "$n"; done
    return 0
}

# Resolve name patterns ("core", "search") to units, matched case-insensitively
# against the unit's id and its name.
units_by_names() {
    local -a all=(); mapfile -t all < <(units)
    local pat u found
    for pat in "$@"; do
        found=""
        for u in "${all[@]}"; do
            if grep -qi -- "$pat" <<<"$u $(unit_name "$u")"; then echo "$u"; found=1; fi
        done
        [ -n "$found" ] || log "No e2e unit matched '${pat}' — skipped" >&2
    done
}

# ── Teardown ──────────────────────────────────────────────────────────────────

# Leftover .tmp-e2e-* work dirs from a crashed run. They may hold root-owned
# container data, so reclaim with a throwaway root container before rm.
sweep_leftover_workdirs() {
    local -a stale=(); local d
    mapfile -t stale < <(find "$REPO_DIR" -maxdepth 1 -type d -name '.tmp-e2e-*' 2>/dev/null)
    for d in "${stale[@]+"${stale[@]}"}"; do
        log "Reclaiming leftover work dir ${d##*/}..."
        docker run --rm -u 0 -v "${d}:/cleanup" alpine \
            sh -c 'rm -rf /cleanup/* /cleanup/.[!.]* 2>/dev/null' 2>/dev/null || true
        rm -rf "$d" 2>/dev/null || log "  warn: could not fully remove ${d##*/}"
    done
}

# `./existential.sh e2e down` — everything is keyed off the compose project
# label, so this never touches the real stack. Also the pre-run reset: our own
# leftovers are always safe to remove, and removing them in this order (containers,
# then networks, then volumes) is what lets a stale volume go at all.
e2e_down() {
    local -a ids=() nets=() vols=(); local id net

    mapfile -t ids < <(docker ps -aq --filter "label=com.docker.compose.project=${E2E_PROJECT}" 2>/dev/null)
    for id in "${ids[@]+"${ids[@]}"}"; do
        docker stop "$id" >/dev/null 2>&1 || true
        docker rm   "$id" >/dev/null 2>&1 || true
    done

    mapfile -t nets < <(docker network ls --filter "label=com.docker.compose.project=${E2E_PROJECT}" --format '{{.Name}}' 2>/dev/null)
    docker network inspect "$E2E_NETWORK" >/dev/null 2>&1 && nets+=("$E2E_NETWORK")
    for net in $(printf '%s\n' "${nets[@]+"${nets[@]}"}" | sort -u); do
        docker network rm "$net" >/dev/null 2>&1 || true
    done

    mapfile -t vols < <(docker volume ls -q --filter "label=com.docker.compose.project=${E2E_PROJECT}" 2>/dev/null)
    [ "${#vols[@]}" -gt 0 ] && docker volume rm "${vols[@]}" >/dev/null 2>&1 || true

    sweep_leftover_workdirs
}

# ── Waiting ───────────────────────────────────────────────────────────────────

# Settled = no created/restarting transients and nothing still "health: starting".
# Best-effort: container-health.sh is the verdict, and it resamples and applies
# its own flap threshold. hermes and open-webui are legitimately "starting" for
# minutes, so a short budget here reports the harness's impatience as a product
# failure.
wait_settled() {
    local work="$1" timeout="${E2E_HEALTH_TIMEOUT:-300}"
    local deadline=$(( $(date +%s) + timeout )) unsettled
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
}

# ── Checks ────────────────────────────────────────────────────────────────────
#
# A check is a decree MESSAGE in checks/ (see checks/README.md) — NOT a migration,
# and the three docs that say so are right: converting them was tried and reverted.
# Its frontmatter is read with e2e_fm_get — the same data decree reads, so the
# two cannot disagree about what the file says.

# There are TWO daemons, each its own decree project with its own machines/,
# inbox/ and runs/, so "the inbox" is a question with two answers. A message for
# a machine its project does not have is a failed run (invalid_message), which
# is how 00-services once failed every run after triage moved projects.
#
# The daemon is DERIVED, never listed: a check names a machine, and the daemon
# that owns it is whichever project has machines/<machine>.yml. `automation` is
# asked first, so a machine both have (notify, clean_runs) runs where it always
# has, and a check's staged sibling machine lands there too, which is where the
# service credentials and the read-write /secrets are. Nothing here enumerates
# checks or machines.
E2E_DAEMONS="automation automation-backup"

# _daemon_dir <daemon> <work> — that daemon's decree project inside the clone.
_daemon_dir() {
    case "$1" in
        automation)        echo "$2/volumes/workspace_data/.decree" ;;
        automation-backup) echo "$2/services/automation-backup" ;;
    esac
}

# check_daemon <work> <md> — the daemon whose project has this check's machine,
# else `automation`.
check_daemon() {
    local work="$1" machine d
    machine="$(e2e_fm_get "$2" machine)"
    if [ -n "$machine" ]; then
        for d in $E2E_DAEMONS; do
            [ -f "$(_daemon_dir "$d" "$work")/machines/${machine}.yml" ] \
                && { echo "$d"; return 0; }
        done
    fi
    echo automation
}

# Checks whose `requires:` vars are all enabled in the clone. A unit without
# nextcloud must not get the file-event probe: staging it anyway would fail a stack that
# is behaving exactly as that unit asked.
applicable_checks() {
    local work="$1" md var missing
    for md in "$CHECK_DIR"/[0-9][0-9]-*.md; do
        [ -f "$md" ] || continue
        missing=""
        for var in $(e2e_fm_get "$md" requires); do
            grep -q "^${var}=true" "$work/.env.shared" || missing="${missing} ${var}"
        done
        [ -n "$missing" ] && { log "  ↷ $(basename "$md" .md) — skipped (off:${missing})" >&2; continue; }
        echo "$md"
    done
    return 0
}

# Stage checks BEFORE render and up, into the shipped set exist.initial.sh seeds
# workspace/.decree from:
#   - a sibling .yml lands in automation/machines/ as <machine>.yml, and a
#     sibling .sh in automation/scripts/ as <machine>.sh (automation-backup
#     mounts that scripts/ too), executable because decree runs scripts by path
#   - a sibling .stage.sh runs on the host, for config already read at boot
#
# The check itself is dropped in later, by drop_checks, once the stack is up —
# it is a message, not a migration. It is COPIED from checks/ rather than
# shipped in flows/, which is what a user's install copies from: test code has
# no business in the product tree.
stage_checks() {
    local work="$1" md m st
    [ -d "$work/automation/machines" ] || { log "  (no decree in this unit — no checks to stage)"; return 0; }

    while IFS= read -r md; do
        [ -n "$md" ] || continue
        m="$(e2e_fm_get "$md" machine)"
        if [ -f "${md%.md}.yml" ]; then
            cp "${md%.md}.yml" "$work/automation/machines/${m}.yml"
            install -m 755 "${md%.md}.sh" "$work/automation/scripts/${m}.sh"
        fi
        st="${md%.md}.stage.sh"
        if [ -f "$st" ]; then
            WORK="$work" REPO_DIR="$REPO_DIR" bash "$st" \
                || die "$(basename "$st") failed — see above"
        fi
    done < <(applicable_checks "$work")
    return 0
}

# _settled <daemon> — true once nothing is running or queued in that daemon
# except a migration that a failed one blocks. A blocked migration is settled,
# not stuck: it will never run, and its failed run is graded like any other.
_settled() {
    docker exec -w /work "$1" sh -c 'decree status --format json | jq -e "
        ([(.runs.finished.failed // [])[].id | . + \".md\"]) as \$failed
        | (.runs.active + .runs.pending | length) == 0
          and (.queued.inbox | length) == 0
          and ((.queued.migrations | length) == 0 or (.queued.migrations[0] as \$m | \$failed | index(\$m)))
    "' >/dev/null 2>&1
}

# _wait_settled <timeout> — every daemon settled, or 1 at the deadline.
_wait_settled() {
    local deadline=$(( $(date +%s) + $1 )) d
    for d in $E2E_DAEMONS; do
        until _settled "$d"; do
            [ "$(date +%s)" -lt "$deadline" ] || { log "  ${d} did not settle within $1s"; return 1; }
            printf '.'
            sleep 5
        done
    done
    echo
}

# Drop the applicable checks into the inbox. Filenames are prefixed so they sort
# after anything decree put there itself.
drop_checks() {
    local work="$1" md d inbox n=0
    [ -d "$(_daemon_dir automation "$work")/inbox" ] || { log "  (no decree inbox — skipping checks)"; return 1; }

    # Wait for the migrations first. Each decree pass drains the inbox BEFORE
    # it runs migrations, so a check dropped now would run ahead of the setup
    # it verifies — 10-file-processing before nextcloud-file-events has
    # registered the webhook it probes.
    log "Waiting for migrations to finish (up to ${E2E_CHECK_TIMEOUT:-900}s)..."
    _wait_settled "${E2E_CHECK_TIMEOUT:-900}" || return 1

    while IFS= read -r md; do
        [ -n "$md" ] || continue
        d="$(check_daemon "$work" "$md")"
        inbox="$(_daemon_dir "$d" "$work")/inbox"
        mkdir -p "$inbox"
        cp "$md" "${inbox}/e2e-$(basename "$md")"
        log "  → $(basename "$md" .md) (${d})"
        n=$(( n + 1 ))
    done < <(applicable_checks "$work")
    [ "$n" -gt 0 ] || { log "  (no checks apply to this unit)"; return 1; }
    return 0
}

# Wait for the daemons to drain: no message queued and no run in flight, in
# either. A failed run does NOT end the wait early, because the daemon carries
# on past one and the remaining checks still have results to produce.
await_checks() {
    log "Waiting for checks to drain (up to ${E2E_CHECK_TIMEOUT:-900}s)..."
    _wait_settled "${E2E_CHECK_TIMEOUT:-900}"
}

# ── Evidence ──────────────────────────────────────────────────────────────────
# The clone is deleted on the way out, so anything not copied here is gone. This
# is what makes a failure readable after the fact instead of only under E2E_KEEP.

collect_unit_results() {
    local work="$1" unit="$2" out slug rc=0 id name state stuck d
    slug="$(printf '%s' "$unit" | tr '[:upper:] ' '[:lower:]-' | tr -cd 'a-z0-9-')"
    out="${E2E_OUT}/$(date '+%Y-%m-%d_%H-%M-%S')-${slug}"

    # Each daemon keeps its own runs/, and a check graded from the wrong one
    # reads as having produced no evidence at all — so grade both.
    local -a runs=() inboxes=()
    for d in $E2E_DAEMONS; do
        runs+=("$(_daemon_dir "$d" "$work")/runs")
        inboxes+=("$(_daemon_dir "$d" "$work")/inbox")
    done
    collect_results "$out" "${runs[@]}" || rc=1

    # Logs for anything the health gate would be unhappy about.
    mkdir -p "$out/logs"
    while IFS= read -r id; do
        [ -n "$id" ] || continue
        state=$(docker inspect --format '{{.State.Status}}{{if .State.Health}} {{.State.Health.Status}}{{end}}' "$id" 2>/dev/null || true)
        case "$state" in "running"|"running healthy") continue ;; esac
        name=$(docker inspect --format '{{.Name}}' "$id" 2>/dev/null | sed 's#^/##')
        docker logs --tail 200 "$id" > "$out/logs/${name:-$id}.log" 2>&1 || true
    done < <(_compose "$work" ps -q 2>/dev/null)
    rmdir "$out/logs" 2>/dev/null || true

    # Messages still queued when the evidence was taken. Not a verdict — the
    # daemon is live by now and its crons queue work of their own — but a check
    # whose chain stalled leaves its trace here, and the clone is about to go.
    stuck=$(find "${inboxes[@]}" -maxdepth 1 -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
    if [ "${stuck:-0}" -gt 0 ]; then
        mkdir -p "$out/stuck"
        find "${inboxes[@]}" -maxdepth 1 -name '*.md' \
            -exec cp {} "$out/stuck/" \; 2>/dev/null || true
        log "  ${stuck} message(s) still queued in the inbox — see ${out#"${REPO_DIR}/"}/stuck/"
    fi

    log "Results → ${out#"${REPO_DIR}/"}/results.md"
    sed -n '/^|/p' "$out/results.md" 2>/dev/null | sed 's/^/[e2e]   /' || true
    return "$rc"
}

# ── Per-unit runner ───────────────────────────────────────────────────────────

WORK=""; UNIT_LABEL=""; COLLECTED=0

cleanup() {
    # Collect first, if the run did not get that far itself — a crash, a failed
    # `up`, or a Ctrl+C is the case that most needs its evidence.
    if [ "$COLLECTED" -eq 0 ] && [ -n "$WORK" ] && [ -d "$(_daemon_dir automation "$WORK")/runs" ]; then
        collect_unit_results "$WORK" "${UNIT_LABEL:-interrupted}" || true
        COLLECTED=1
    fi
    if [ "${E2E_KEEP:-}" = "1" ] && [ -n "$WORK" ]; then
        log "E2E_KEEP=1 — leaving the stack up. Clean up: ./existential.sh e2e down"
        log "  containers: docker compose -p ${E2E_PROJECT} -f ${WORK}/docker-compose.yml ps"
        WORK=""; return 0
    fi
    if [ -n "$WORK" ] && [ -f "$WORK/docker-compose.yml" ]; then
        log "Tearing down..."
        _compose "$WORK" down -v --remove-orphans 2>/dev/null || true
    fi
    docker network rm "$E2E_NETWORK" 2>/dev/null || true
    if [ -n "$WORK" ] && [ -d "$WORK" ]; then
        # Containers write files owned by their internal UIDs, not the host user.
        docker run --rm -u 0 -v "${WORK}:/cleanup" alpine \
            sh -c 'rm -rf /cleanup/*' 2>/dev/null || true
        rm -rf "$WORK" 2>/dev/null || true
    fi
    WORK=""
}
# Signals raise an exit rather than running cleanup directly: an INT/TERM
# handler RETURNS to where it interrupted, so the run would carry on against a
# $WORK that cleanup had just blanked and report FAILED when the truth was that
# someone pressed Ctrl+C.
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

run_unit() {
    local unit="$1" name vendor var src f n=0 health_rc=0 checks_rc=0
    name=$(unit_name "$unit")

    hr; log "${name} — start"; hr
    UNIT_LABEL="$name"; COLLECTED=0
    WORK="${REPO_DIR}/.tmp-e2e-$(date '+%Y-%m-%d_%H-%M')-$$"
    mkdir -p "$WORK"

    # 1. The WORKING TREE, not HEAD — uncommitted work is what gets tested.
    #    `ls-files --cached --others --exclude-standard` is `git add -A`'s view,
    #    so git's own ignore rules keep .env, volumes/, rendered compose files
    #    and e2e-out/ out, exactly as they keep them out of a commit. Filtered by
    #    what is on disk, so an unstaged delete reads as deleted here too. tar,
    #    not cp: existential.sh and the hook scripts are dead without their +x.
    log "Creating fresh clone..."
    while IFS= read -r -d '' src; do
        [ -e "${REPO_DIR}/${src}" ] || [ -L "${REPO_DIR}/${src}" ] || continue
        printf '%s\0' "$src"
    done < <(git -C "$REPO_DIR" ls-files -z --cached --others --exclude-standard) \
        | tar -C "$REPO_DIR" -cf - --null -T - | tar -xf - -C "$WORK"

    # 2. Fixture .env.shared (bypasses the render's prompts). Containers run as
    #    the host user, which existential.sh's _ensure_host_ids does for a real
    #    run; e2e renders directly, so the bind-mount dirs would not match.
    cp "$FIXTURES/env.shared" "$WORK/.env.shared"
    grep -q '^EXIST_PUID=' "$WORK/.env.shared" || printf 'EXIST_PUID=%s\n' "$(id -u)" >> "$WORK/.env.shared"
    grep -q '^EXIST_PGID=' "$WORK/.env.shared" || printf 'EXIST_PGID=%s\n' "$(id -g)" >> "$WORK/.env.shared"

    # 3. Core's services, then the flow's: its own and those of every flow it
    #    needs. The vendor answer outranks the list, as `flow on` does.
    log "Enabling services..."
    vendor=$(grep -m1 '^EXIST_GPU_VENDOR=' "$WORK/.env.shared" | cut -d= -f2-)
    for var in $(grep -oE '^EXIST_IS_[A-Z_]+=true' "$WORK/.env.exist.shared" | cut -d= -f1) \
               $( [ "$unit" = core ] || for f in $(flow_closure "$unit"); do flow_list "$f" services; done ); do
        if [ -n "$vendor" ] && vendor_forbids_service "$vendor" "$var"; then
            log "  skipping ${var} — EXIST_GPU_VENDOR=${vendor}"
            continue
        fi
        # Verified, not fired and forgotten. This sed is a silent no-op when the
        # key is absent from the fixture, and the fixture had drifted seven keys
        # behind .env.exist.shared — so Core quietly came up WITHOUT openviking,
        # firecrawl, wyoming-whisper and wyoming-piper, and stayed green because
        # nothing checked. Rendering then appends the missing key as `false`,
        # which is why the stack looked deliberate rather than broken. Adding a
        # service must not be able to rot this fixture in silence.
        sed -i "s|^${var}=false|${var}=true|" "$WORK/.env.shared"
        grep -q "^${var}=true" "$WORK/.env.shared" \
            || die "could not enable ${var} — add it to src/test/fixtures/env.shared"
    done

    # 4. The flow's files: its migrations, cron files and file processors, and
    #    those of every flow it needs. Core's default flows arrive with
    #    exist.initial.sh, below, exactly as on a real install.
    if [ "$unit" != core ]; then
        for f in $(flow_closure "$unit"); do
            n=$(( n + $(REPO_DIR="$WORK" flow_activate "$f" | wc -l) ))
        done
    fi
    log "Activated ${n} flow files"

    # 5. Stage the checks — before the render, because what this touches
    #    (machines/ and scripts/, seeded by exist.initial.sh, and the webhook route table) is read at boot.
    log "Staging checks..."
    stage_checks "$WORK"

    log "Rendering templates..."
    docker compose -p "$E2E_PROJECT" -f "$WORK/existential-compose.yml" run --rm \
        --user "$(id -u):$(id -g)" --entrypoint "" \
        -e REPO_DIR=/repo -e FORCE=false existential-adhoc bash /src/templates.sh

    # 6. exist.initial.sh, exactly as a real install gets it — caddy's
    #    internal.pem is minted here and its Caddyfile hard-references it.
    #    Sourced from the CLONE's existential.sh so this cannot drift from the
    #    real run_initials; the subshell keeps its set -e and SCRIPT_DIR out of
    #    ours.
    log "Running exist.initial.sh for enabled services..."
    ( . "$WORK/existential.sh"; run_initials ) \
        || die "exist.initial.sh failed for one or more services — see above"

    # 6b. Strip the daemon's crons. They fire on a */5 schedule against a stack
    #     that lives for a single run, so whether one lands inside the window is
    #     a coin toss — the same tree produced 10 rows and 12 rows on consecutive
    #     runs, and evidence that changes run to run is not evidence.
    #
    #     Nothing that can FAIL is lost: triage exits 0 even with services down
    #     by design (its verdict rides the exist_service_healthy gauge and ntfy,
    #     not the exit code) and the notify it queues follows it. What a cron
    #     does on a schedule is triage's job on the real stack, continuously —
    #     which is exactly why e2e stopped running a per-service tier at all.
    rm -f "$(_daemon_dir automation "$WORK")/cron/"*.md \
          "$WORK/services/automation-backup/cron/"*.md

    # 7. $WORK is passed as the host-side repo root so the generated bind-mount
    #    paths resolve on the host, not inside adhoc.
    log "Generating docker-compose.yml..."
    docker compose -p "$E2E_PROJECT" -f "$WORK/existential-compose.yml" run --rm \
        --user "$(id -u):$(id -g)" --entrypoint "" existential-adhoc \
        tsx /src/generate-compose.ts /repo docker-compose.yml "$WORK"
    [ -f "$WORK/docker-compose.yml" ] || die "generate-compose.ts produced no docker-compose.yml"

    # 8. --build is mandatory: compose reuses a cached image and never rebuilds
    #    on a Dockerfile change, which is how a crash-looping decree once passed.
    log "Starting services..."
    _compose "$WORK" up -d --build
    wait_settled "$WORK"

    # 9. Container-state gate. The only place with docker visibility, so it is
    #    where daemon liveness (decree, decree-backup — no HTTP surface) is checked.
    bash "${REPO_DIR}/src/test/integration/container-health.sh" \
        "$WORK/docker-compose.yml" "$E2E_PROJECT" || health_rc=1
    [ "$health_rc" -eq 0 ] || log "${name} — container health gate FAILED"

    # 10. The checks, dropped now and not earlier: a check asks whether the
    #     stack WORKS, and that question is only meaningful once it has finished
    #     starting. Run as migrations (during decree's boot) they failed hermes,
    #     appsmith, lowcoder, nocodb and nextcloud on stacks the health gate
    #     then found healthy. An unhealthy container does not skip them — the
    #     rest still have results worth collecting.
    drop_checks "$WORK" || checks_rc=1
    [ "$checks_rc" -eq 0 ] && { await_checks "$WORK" || checks_rc=1; }

    collect_unit_results "$WORK" "$name" || checks_rc=1
    COLLECTED=1

    [ "$health_rc" -eq 0 ] && [ "$checks_rc" -eq 0 ] || return 1
    log "${name} — PASSED"
    cleanup
}

# ── Main ──────────────────────────────────────────────────────────────────────

# One e2e run at a time, machine-wide. The compose project and every container
# name are fixed globals, so a second run's e2e_down tears the FIRST run's stack
# down mid-flight — seen as "No such container" and FAIL (status=) on a run that
# was otherwise perfectly healthy. `down` takes the lock too: reclaiming
# artifacts while a run is using them is the same collision.
#
# The lock lives in /tmp rather than the repo because the collision is global —
# two different clones of this repo would fight over the same container names.
# Same fd-9 idiom as openviking-index-dir.sh: held for the life of the process,
# so a crash or a kill frees it and there is no stale lock to clean up. That
# routine SKIPS when it loses the race because a cron will come round again;
# this one is run by a person, so it says so and stops.
_LOCK="${TMPDIR:-/tmp}/exist-e2e.lock"
exec 9>"$_LOCK"
if ! flock -n 9; then
    die "another e2e run is already in progress — see: pgrep -af e2e.sh"
fi

if [ "${1:-}" = "down" ]; then
    e2e_down
    log "e2e teardown complete."
    exit 0
fi

# Our own leftovers are always safe to remove, and a previous crash can leave
# containers holding the names this run needs.
e2e_down

log "Building existential-adhoc image..."
docker compose -p "$E2E_PROJECT" -f "${REPO_DIR}/existential-compose.yml" build existential-adhoc

declare -a SELECTED=()
if [ "$#" -gt 0 ]; then
    mapfile -t SELECTED < <(units_by_names "$@" | awk '!seen[$0]++')
    [ "${#SELECTED[@]}" -gt 0 ] || die "No e2e unit matched: $*"
else
    mapfile -t SELECTED < <(units)
fi

log "Selected:"
for u in "${SELECTED[@]}"; do log "  • $(unit_name "$u")"; done

declare -a PASS=() FAIL=()
for u in "${SELECTED[@]}"; do
    name=$(unit_name "$u")
    if run_unit "$u"; then
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
