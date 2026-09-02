#!/usr/bin/env bash
# e2e.sh — does a FRESH INSTALL come up working?
#
# That question is the whole remit, and it is the one nothing else in this repo
# answers: `triage` already runs every enabled service's exist.test.sh on the
# real stack every five minutes, so per-service health needs no second home
# here. What triage cannot see is a first install — templates rendering,
# migrations running, one service reaching another for the first time.
#
# Per selected quest: copy the WORKING TREE into a throwaway clone (tracked
# files plus untracked-but-not-ignored ones, so uncommitted work is what gets
# tested and secrets stay out by git's own ignore rules), enable the quest's
# services, apply its copies:, render, up, then drop this run's CHECKS into the
# decree inbox once the stack is healthy and let the daemon run them. Evidence
# lands in e2e-out/ before teardown.
#
# A check is a markdown file in checks/ — a decree message, run after the stack
# is up because that is when "does it work?" can be asked. Adding a check is
# adding a file; nothing here enumerates them.
#
# Usage (via existential.sh):
#   ./existential.sh e2e                 # every e2e-able quest
#   ./existential.sh e2e automation      # quests matching a name/filename pattern
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
QUEST_DIR="${REPO_DIR}/src/quests"

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

# ── Quest frontmatter ─────────────────────────────────────────────────────────
# Scalars come from e2e_fm_get (results.sh). quest_fm survives for the two
# LISTS, which a single-key reader cannot express. Everything is scoped to the
# frontmatter: a guide that happens to show a `- var:` line in an example is
# prose, not config.

quest_fm()   { awk 'NR==1 && /^---$/{f=1;next} f && /^---$/{exit} f' "$1"; }
quest_name() { e2e_fm_get "$1" name; }
quest_vars() { quest_fm "$1" | grep '^\s*- var:' | awk '{print $3}'; }

# The quest's `copies:` — the migrations and cron files quest.sh installs for a
# real install. Emits "src<TAB>dst<TAB>requires". Parsed here rather than with
# yq because e2e.sh runs on the HOST, which has no yq (quest.sh has one; it runs
# in adhoc). Skipping this is how every ollama and minio migration came to be a
# silent no-op under e2e.
quest_copies() {
    quest_fm "$1" | awk '
        /^copies:[[:space:]]*$/ { in_copies = 1; next }
        in_copies && /^[^ \t-]/ { in_copies = 0 }
        !in_copies { next }
        /^[[:space:]]*-[[:space:]]*src:/ {
            if (src != "") print src "\t" dst "\t" req
            src = $0; sub(/^[^:]*:[[:space:]]*/, "", src); dst = ""; req = ""; next
        }
        /^[[:space:]]*dst:/      { dst = $0; sub(/^[^:]*:[[:space:]]*/, "", dst); next }
        /^[[:space:]]*requires:/ { req = $0; sub(/^[^:]*:[[:space:]]*/, "", req); next }
        END { if (src != "") print src "\t" dst "\t" req }
    '
}

# Quests with e2e: false need external infrastructure (NAS/NFS, DNS, TLS) and
# are excluded; validate-conventions.ts makes them carry an e2e_skip: reason.
automatable_quests() {
    local yaml
    for yaml in "${QUEST_DIR}"/[0-9][0-9]-*.md; do
        [ "$(e2e_fm_get "$yaml" e2e)" = true ] && echo "$yaml"
    done
    return 0
}

# Resolve name patterns ("automation", "ai finance") to quest paths, matched
# case-insensitively against the quest's name: and its filename.
quests_by_names() {
    local -a all=(); mapfile -t all < <(automatable_quests)
    local pat yaml found
    for pat in "$@"; do
        found=""
        for yaml in "${all[@]}"; do
            if grep -qi -- "$pat" <<<"$(quest_name "$yaml")" \
            || grep -qi -- "$pat" <<<"$(basename "$yaml" .md)"; then
                echo "$yaml"; found=1
            fi
        done
        [ -n "$found" ] || log "No e2e-able quest matched '${pat}' — skipped" >&2
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
# A check is a decree MIGRATION in checks/ (see checks/README.md). Its
# frontmatter is read with e2e_fm_get — the same data decree reads, so the two
# cannot disagree about what the file says.

# Checks whose `requires:` vars are all enabled in the clone. A quest without
# minio must not get the minio probe: staging it anyway would fail a stack that
# is behaving exactly as that quest asked.
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

# Stage checks BEFORE render and up: everything here is read once at container
# start, which is exactly why a check cannot do it to itself.
#   - the check itself lands in the clone's migrations/, keeping its NUMBER, so
#     decree runs it in the same pass as the product's own migrations
#   - a sibling .sh lands in shared_routines/ and is registered enabled
#   - each check's needs_routines are switched on
#   - max_attempts drops to 1, so a failing check costs one run, not three
#   - a sibling .stage.sh runs on the host, for config already read at boot
#
# The check is COPIED here rather than shipped in migrations.example/, which is
# what a user's quest copies from: test code has no business in the product tree.
stage_checks() {
    local work="$1" md sh st cfg r
    cfg="$work/services/decree/decree/config.exist.yml"
    [ -f "$cfg" ] || { log "  (no decree in this quest — no checks to stage)"; return 0; }
    sed -i 's/^max_attempts:.*/max_attempts: 1/' "$cfg"

    local -a enable=() needs=()
    while IFS= read -r md; do
        [ -n "$md" ] || continue
        sh="${md%.md}.sh"
        if [ -f "$sh" ]; then
            cp "$sh" "$work/automations/shared_routines/$(e2e_fm_get "$md" routine).sh"
            enable+=("$(e2e_fm_get "$md" routine)")
        fi
        # needs_routines is a space-separated list, so splitting is the point.
        needs=(); read -r -a needs <<<"$(e2e_fm_get "$md" needs_routines)"
        enable+=("${needs[@]+"${needs[@]}"}")
        st="${md%.md}.stage.sh"
        if [ -f "$st" ]; then
            WORK="$work" REPO_DIR="$REPO_DIR" bash "$st" \
                || die "$(basename "$st") failed — see above"
        fi
    done < <(applicable_checks "$work")

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

# ── Evidence ──────────────────────────────────────────────────────────────────
# The clone is deleted on the way out, so anything not copied here is gone. This
# is what makes a failure readable after the fact instead of only under E2E_KEEP.

collect_quest_results() {
    local work="$1" quest="$2" out slug rc=0 id name state stuck
    slug="$(printf '%s' "$quest" | tr '[:upper:] ' '[:lower:]-' | tr -cd 'a-z0-9-')"
    out="${E2E_OUT}/$(date '+%Y-%m-%d_%H-%M-%S')-${slug}"

    collect_results "$work/automations/runs" \
                    "$work/services/decree/decree/inbox/dead" "$out" || rc=1

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
    stuck=$(find "$work/services/decree/decree/inbox" -maxdepth 1 -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
    if [ "${stuck:-0}" -gt 0 ]; then
        mkdir -p "$out/stuck"
        find "$work/services/decree/decree/inbox" -maxdepth 1 -name '*.md' \
            -exec cp {} "$out/stuck/" \; 2>/dev/null || true
        log "  ${stuck} message(s) still queued in the inbox — see ${out#"${REPO_DIR}/"}/stuck/"
    fi

    log "Results → ${out#"${REPO_DIR}/"}/results.md"
    sed -n '/^|/p' "$out/results.md" 2>/dev/null | sed 's/^/[e2e]   /' || true
    return "$rc"
}

# ── Per-quest runner ──────────────────────────────────────────────────────────

WORK=""; QUEST_LABEL=""; COLLECTED=0

cleanup() {
    # Collect first, if the run did not get that far itself — a crash, a failed
    # `up`, or a Ctrl+C is the case that most needs its evidence.
    if [ "$COLLECTED" -eq 0 ] && [ -n "$WORK" ] && [ -d "$WORK/automations/runs" ]; then
        collect_quest_results "$WORK" "${QUEST_LABEL:-interrupted}" || true
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

run_quest() {
    local yaml="$1" name vendor var src dst req n=0 health_rc=0 checks_rc=0
    name=$(quest_name "$yaml")

    hr; log "${name} — start"; hr
    QUEST_LABEL="$name"; COLLECTED=0
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

    # 2. Fixture .env.shared (bypasses the EXIST_CLI prompts). Containers run as
    #    the host user, which existential.sh's _ensure_host_ids does for a real
    #    run; e2e renders directly, so the bind-mount dirs would not match.
    cp "$FIXTURES/env.shared" "$WORK/.env.shared"
    grep -q '^EXIST_PUID=' "$WORK/.env.shared" || printf 'EXIST_PUID=%s\n' "$(id -u)" >> "$WORK/.env.shared"
    grep -q '^EXIST_PGID=' "$WORK/.env.shared" || printf 'EXIST_PGID=%s\n' "$(id -g)" >> "$WORK/.env.shared"

    # 3. Enable the quest's services, plus decree unconditionally — it is where
    #    the checks RUN, and four e2e-able quests do not list it, which would
    #    render a stack with nothing able to test it.
    log "Enabling services..."
    sed -i 's|^EXIST_IS_SERVICES_DECREE=false|EXIST_IS_SERVICES_DECREE=true|' "$WORK/.env.shared"
    vendor=$(grep -m1 '^EXIST_GPU_VENDOR=' "$WORK/.env.shared" | cut -d= -f2-)
    for var in $(quest_vars "$yaml"); do
        # The quest lists what it wants; the vendor answer outranks it, the same
        # rule quest.sh applies to a real install from the same list.
        if [ -n "$vendor" ] && vendor_forbids_service "$vendor" "$var"; then
            log "  skipping ${var} — EXIST_GPU_VENDOR=${vendor}"
            continue
        fi
        sed -i "s|^${var}=false|${var}=true|" "$WORK/.env.shared"
    done

    # 4. The quest's copies: — its migrations and cron files. requires: is
    #    answered against the .env.shared step 3 has just written.
    while IFS=$'\t' read -r src dst req; do
        [ -n "$src" ] || continue
        [ -n "$req" ] && ! grep -q "^${req}=true" "$WORK/.env.shared" && continue
        [ -f "$WORK/$src" ] || { log "  warn: ${src} not in the clone — skipped"; continue; }
        mkdir -p "$WORK/${dst%/}"
        cp -n "$WORK/$src" "$WORK/${dst%/}/${src##*/}" 2>/dev/null || continue
        n=$(( n + 1 ))
    done < <(quest_copies "$yaml")
    log "Applied ${n} quest copies"

    # 5. Stage the checks — before the render, because what this touches
    #    (decree's routine whitelist, the webhook route table) is read at boot.
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
    rm -f "$WORK/services/decree/decree/cron/"*.md \
          "$WORK/services/decree/decree-backup/cron/"*.md

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

    collect_quest_results "$WORK" "$name" || checks_rc=1
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
    mapfile -t SELECTED < <(quests_by_names "$@" | awk '!seen[$0]++')
    [ "${#SELECTED[@]}" -gt 0 ] || die "No e2e-able quests matched: $*"
else
    mapfile -t SELECTED < <(automatable_quests)
    [ "${#SELECTED[@]}" -gt 0 ] || die "No automatable quests found."
fi

log "Selected quests:"
for yaml in "${SELECTED[@]}"; do log "  • $(quest_name "$yaml")"; done

declare -a PASS=() FAIL=()
for yaml in "${SELECTED[@]}"; do
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
