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
#
# Read-only re: the real repo — all writes are in mktemp dirs cleaned on exit.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RUN_ALL="$ROOT/src/test/run-all.sh"
HEALTH="$ROOT/src/test/integration/container-health.sh"

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

echo ""
if [ "$fail" -ne 0 ]; then
    echo "  The test harness did NOT report a failure it should have — false confidence." >&2
    exit 1
fi
echo "  PASS  harness-selftest (runner + container-health surface failures)"
exit 0
