#!/usr/bin/env bash
# harness-selftest.sh — prove the TEST HARNESS itself reports failures.
#
# Companion to guard-selftest.sh. Where that one proves the secret *guards*
# trip, this proves the *test plumbing* does: a test suite that silently swallows
# a failing assertion is worse than no test (it manufactures false confidence).
# The audit found exactly this twice — validate-conventions "passed vacuously"
# and the pre-commit grep bug errored yet returned success.
#
# Two mechanisms, both host-side (no adhoc/docker needed — they are faked):
#   1. run-all.sh aggregation: a failing unit test must make the runner exit
#      non-zero AND surface that test by name.
#   2. container-health.sh: an exited/unhealthy container must make the gate
#      exit non-zero (driven by a fake `docker`, so no real containers spin up).
#   3. e2e's collect_results: a failing check must be graded FAIL and must fail
#      the run. e2e was the one piece of test plumbing with no opposite — the
#      harness silently passing is the exact rot this file exists to catch.
#
# Read-only re: the real repo — all writes are in mktemp dirs cleaned on exit.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RUN_ALL="$ROOT/src/test/run-all.sh"
HEALTH="$ROOT/src/test/integration/container-health.sh"
# shellcheck source=e2e/results.sh
. "$ROOT/src/test/e2e/results.sh"

fail=0
pass()  { echo "  PASS  $*"; }
flunk() { echo "  FAIL  $*" >&2; fail=1; }

# One parent temp dir, cleaned as a unit — avoids the subshell-array pitfall
# where TMPS+= inside a $(...) command substitution never reaches the parent.
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mktmp() { mktemp -d "$WORK/t.XXXXXX"; }

# ── 1. run-all.sh surfaces a failing suite ────────────────────────────────────
# Copy the real run-all.sh into a throwaway tree with synthetic unit tests; it
# discovers unit/test-*.sh relative to its own location, so this exercises the
# real run()/aggregation/exit-gate code, not a reimplementation.
echo "[harness-selftest] run-all.sh failure aggregation"

make_runner_tree() {                 # $1=dir  $2=include-failing(yes/no)
    local d="$1"
    cp "$RUN_ALL" "$d/run-all.sh"
    mkdir -p "$d/unit"
    printf '#!/usr/bin/env bash\necho "  PASS  always-green"\nexit 0\n' > "$d/unit/test-aaa-green.sh"
    if [ "$2" = yes ]; then
        printf '#!/usr/bin/env bash\necho "  FAIL  always-red"\nexit 1\n' > "$d/unit/test-zzz-red.sh"
    fi
}

d="$(mktmp)"; make_runner_tree "$d" yes
out=""; rc=0
out="$(bash "$d/run-all.sh" unit 2>&1)" || rc=$?
if [ "$rc" -ne 0 ]; then pass "failing suite → runner exits non-zero"
else flunk "failing suite did NOT fail the runner (rc=$rc)"; fi
if grep -q 'zzz-red' <<<"$out" && grep -q '1 failed' <<<"$out"; then
    pass "failing suite surfaced by name in summary"
else
    flunk "runner did not surface the failing suite"; printf '%s\n' "$out" >&2
fi

d="$(mktmp)"; make_runner_tree "$d" no
rc=0; bash "$d/run-all.sh" unit >/dev/null 2>&1 || rc=$?
if [ "$rc" -eq 0 ]; then pass "all-green suites → runner exits zero"
else flunk "all-green run wrongly failed (rc=$rc)"; fi

# ── 2. container-health.sh trips on a bad container ───────────────────────────
# A fake `docker` lets us drive the failure path deterministically with no real
# containers. FAKE_STATE is what the combined State inspect returns.
echo "[harness-selftest] container-health.sh state gate"

d="$(mktmp)"
FAKE_DOCKER="$d/docker"
cat > "$FAKE_DOCKER" <<'FAKE'
#!/usr/bin/env bash
case "$1" in
    compose) echo fakeid1 ;;                      # `compose ... ps -q`
    inspect)
        case "$3" in                              # $3 = -f format string
            *Name*)            echo "/fake-svc" ;;
            "{{.RestartCount}}") echo 0 ;;
            *Mounts*)          echo "${FAKE_MOUNTS:-}" ;;
            *)                 echo "${FAKE_STATE:-running 0 none}" ;;
        esac ;;
    logs) echo "fake log line" ;;
esac
FAKE
chmod +x "$FAKE_DOCKER"
COMPOSE_FILE="$d/docker-compose.yml"; : > "$COMPOSE_FILE"   # must exist; content unused (docker is faked)

rc=0
FAKE_STATE="exited 0 none" DOCKER_CMD="$FAKE_DOCKER" \
    bash "$HEALTH" "$COMPOSE_FILE" "" 0 >/dev/null 2>&1 || rc=$?
if [ "$rc" -ne 0 ]; then pass "exited container → gate exits non-zero"
else flunk "exited container did NOT fail the gate (rc=$rc)"; fi

rc=0
FAKE_STATE="running 0 healthy" DOCKER_CMD="$FAKE_DOCKER" \
    bash "$HEALTH" "$COMPOSE_FILE" "" 0 >/dev/null 2>&1 || rc=$?
if [ "$rc" -eq 0 ]; then pass "healthy running container → gate exits zero"
else flunk "healthy container wrongly failed the gate (rc=$rc)"; fi

# One restart that has SETTLED is not a loop. homeassistant's entrypoint exits
# once by design on a cold first boot (it can only write .storage/http while HA
# is stopped), so a gate that fails on a single advance fails every correct
# first install. RestartCount sits at 1 across both windows here.
rc=0
FAKE_STATE="running 1 healthy" DOCKER_CMD="$FAKE_DOCKER" \
    bash "$HEALTH" "$COMPOSE_FILE" "" 0 >/dev/null 2>&1 || rc=$?
if [ "$rc" -eq 0 ]; then pass "one settled restart → gate exits zero"
else flunk "a single settled restart wrongly failed the gate (rc=$rc)"; fi

# ...but a count that is STILL advancing on the second window is a real loop.
# This fake increments RestartCount on every combined-state inspect, so the
# second window always sees a higher number than the first.
FAKE_LOOP="$d/docker-looping"
cat > "$FAKE_LOOP" <<'FAKE'
#!/usr/bin/env bash
case "$1" in
    compose) echo fakeid1 ;;
    inspect)
        case "$3" in
            *Name*)              echo "/fake-svc" ;;
            "{{.RestartCount}}") echo 0 ;;
            *Mounts*)            echo "" ;;
            *)  n=$(cat "${FAKE_COUNTER}" 2>/dev/null || echo 0)
                n=$((n + 1)); echo "$n" > "${FAKE_COUNTER}"
                echo "running $n none" ;;
        esac ;;
    logs) echo "fake log line" ;;
esac
FAKE
chmod +x "$FAKE_LOOP"
rc=0
FAKE_COUNTER="$d/count" DOCKER_CMD="$FAKE_LOOP" \
    bash "$HEALTH" "$COMPOSE_FILE" "" 0 >/dev/null 2>&1 || rc=$?
if [ "$rc" -ne 0 ]; then pass "still-advancing RestartCount → gate exits non-zero"
else flunk "an active restart loop did NOT fail the gate (rc=$rc)"; fi

# A Docker-managed volume is invisible to the generated compose file, so this
# gate is the only thing that can catch one. It must fail even when the
# container is otherwise perfectly healthy.
rc=0
FAKE_STATE="running 0 healthy" FAKE_MOUNTS="/var/www/html " DOCKER_CMD="$FAKE_DOCKER" \
    bash "$HEALTH" "$COMPOSE_FILE" "" 0 >/dev/null 2>&1 || rc=$?
if [ "$rc" -ne 0 ]; then pass "Docker-managed volume → gate exits non-zero"
else flunk "anonymous volume did NOT fail the gate (rc=$rc)"; fi

# ── 3. collect_results grades e2e checks ──────────────────────────────────────
# A fabricated runs/ tree — no stack, no Docker. decree mirrors a run's state
# into its message.md, and only `done` is a pass.
echo "[harness-selftest] e2e collect_results grading"

# run <runs_dir> <id> <frontmatter lines> — one fabricated run
run() {
    mkdir -p "$1/$2"
    printf -- '---\n%b\n---\n' "$3" > "$1/$2/message.md"
    printf '{"duration_ms":3000,"state":"x","type":"run_finished"}\n' > "$1/$2/events.jsonl"
    echo "boom" > "$1/$2/0001-go-x.log"
}

# $1=dir  $2=state of the second check (done|failed|none)
make_runs_tree() {
    local d="$1" kind="$2"
    mkdir -p "$d/runs" "$d/out"
    run "$d/runs" r-green 'machine: triage\ne2e_check: 00-green\nstate: done'
    case "$kind" in
        done)   run "$d/runs" r-two 'e2e_check: 10-two\nstate: done' ;;
        failed) run "$d/runs" r-two 'e2e_check: 10-two\nstate: failed' ;;
        none)   run "$d/runs" r-two 'e2e_check: 10-two' ;;
    esac
}

for kind in "failed:failing" "none:still-running"; do
    label="${kind#*:}"; kind="${kind%%:*}"
    d="$(mktmp)"; make_runs_tree "$d" "$kind"
    rc=0; collect_results "$d/out" "$d/runs" >/dev/null 2>&1 || rc=$?
    if [ "$rc" -ne 0 ]; then pass "a ${label} check → collect_results reports failure"
    else flunk "a ${label} check was graded as a PASS (rc=$rc)"; fi
    if grep -q '10-two' "$d/out/results.md" 2>/dev/null && grep -q '✗' "$d/out/results.md"; then
        pass "a ${label} check is named and marked ✗ in results.md"
    else
        flunk "results.md did not surface the ${label} check"
        cat "$d/out/results.md" 2>&1 >&2 || true
    fi
done

d="$(mktmp)"; make_runs_tree "$d" "done"
rc=0; collect_results "$d/out" "$d/runs" >/dev/null 2>&1 || rc=$?
if [ "$rc" -eq 0 ]; then pass "all-green checks → collect_results reports success"
else flunk "all-green checks wrongly reported failure (rc=$rc)"; fi

# Evidence has to survive teardown — that is the whole reason the directory
# exists. If the script log is not copied, a failure is unreadable after the run.
d="$(mktmp)"; make_runs_tree "$d" failed
collect_results "$d/out" "$d/runs" >/dev/null 2>&1 || true
if [ -f "$d/out/r-two/0001-go-x.log" ] && [ -f "$d/out/r-two/events.jsonl" ]; then
    pass "a failing check's log and events are copied out"
else
    flunk "failing check evidence was not copied into the output dir"
fi

# The work a check TRIGGERS carries no e2e_check key of its own, and grading only
# the named checks let a live run report PASS while the router failed on every
# event it routed. Every run in the clone has to count.
d="$(mktmp)"; make_runs_tree "$d" "done"
run "$d/runs" r-downstream 'machine: file_router\nstate: failed'
rc=0; collect_results "$d/out" "$d/runs" >/dev/null 2>&1 || rc=$?
if [ "$rc" -ne 0 ]; then pass "a failing run with no e2e_check → reports failure"
else flunk "a failing downstream run was not graded (rc=$rc)"; fi
if grep -q 'file_router' "$d/out/results.md" 2>/dev/null; then
    pass "an unnamed failing run is named by its machine in results.md"
else
    flunk "results.md did not name the failing downstream run"
fi

# Each decree daemon keeps its own runs/, so collect_results takes every one.
# Reading only the first is how a check the second daemon ran would come back
# as no evidence at all.
d="$(mktmp)"; make_runs_tree "$d" "done"
run "$d/runs-backup" r-svc 'machine: triage\ne2e_check: 00-services\nstate: failed'
rc=0; collect_results "$d/out" "$d/runs" "$d/runs-backup" >/dev/null 2>&1 || rc=$?
if [ "$rc" -ne 0 ] && grep -q '00-services' "$d/out/results.md" 2>/dev/null; then
    pass "a failed run in the second daemon's runs/ → reports failure"
else
    flunk "a failed run outside the first runs/ was not graded (rc=$rc)"
fi

# A run that verified nothing must not read as a pass. This is the silent-rot
# case: checks that never got dropped, or a decree that never started, would
# otherwise leave an empty runs/ and a green e2e.
d="$(mktmp)"; mkdir -p "$d/runs" "$d/out"
rc=0; collect_results "$d/out" "$d/runs" >/dev/null 2>&1 || rc=$?
if [ "$rc" -ne 0 ]; then pass "zero checks → collect_results reports failure"
else flunk "a run with no checks at all was graded as a PASS"; fi

echo ""
if [ "$fail" -ne 0 ]; then
    echo "  The test harness did NOT report a failure it should have — false confidence." >&2
    exit 1
fi
echo "  PASS  harness-selftest (runner + container-health surface failures)"
exit 0
