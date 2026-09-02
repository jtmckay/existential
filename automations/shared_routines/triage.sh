#!/usr/bin/env bash
# Triage — run every enabled service's own test, and say plainly what is broken.
#
# The problem this solves: on a first `docker compose up -d` something is always
# half-wrong, and the symptom the user sees is "the dashboard tile is grey".
# Finding out why means knowing that `./existential.sh test services` exists.
# Triage is that command, run for you, on a schedule that gets out of the way.
#
# ── Why it is on by default ──────────────────────────────────────────────────
#
# The person who most needs triage is the one who does not know it exists. A
# mode you have to discover and enable helps nobody on their first hour. So it
# runs from the start and QUIETS ITSELF instead of waiting to be turned off:
# every consecutive all-green round pushes the next check further out
# (TRIAGE_BACKOFF), up to TRIAGE_MAX_INTERVAL. A stack that comes up clean is
# checked a few times and then left alone; a stack that does not stays under
# close watch until it does.
#
# The other half of not being noise: it notifies on CHANGE, never on state. A
# service that has been failing since yesterday does not page you again. What
# reaches ntfy is "this broke" and "this recovered", which are the only two
# events worth interrupting someone for.
#
# ── What it runs ─────────────────────────────────────────────────────────────
#
# Each enabled service's own exist.test.sh — the same authoritative check
# `./existential.sh test services` runs, and the same one the migration gate
# retries at startup. Nothing is configured per service: enablement is read from
# .env.shared, so a service added tomorrow is triaged tomorrow with no cron file
# to write. That is the point — service-health probes ONE url you named, this
# probes everything you have.
#
# Requires the repo mounted read-only at /repo (services/decree's compose does
# this) because the tests live with their services.
#
# ── Frontmatter / env ────────────────────────────────────────────────────────
#   TRIAGE_BACKOFF        minutes per step: "5 5 15 30 60" (default below)
#   TRIAGE_MAX_INTERVAL   minutes; the floor it settles to (default 360)
#   TRIAGE_NOTIFY         notify on change (default true)
#   TRIAGE_ALWAYS         ignore backoff and run every tick (default false)
#   TRIAGE_REPO           repo mount (default /repo)
#   TRIAGE_STRICT         exit non-zero when a service failed (default false)
#
#   ---
#   cron: "*/5 * * * *"
#   routine: triage
#   ---
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

message_file="${message_file:-}"
message_id="${message_id:-}"
message_dir="${message_dir:-}"

TRIAGE_REPO="${TRIAGE_REPO:-/repo}"
TRIAGE_STATE="${TRIAGE_STATE:-/data/triage/state.env}"
TRIAGE_REPORT="${TRIAGE_REPORT:-/data/triage/status.md}"
TRIAGE_BACKOFF="${TRIAGE_BACKOFF:-5 5 15 30 60}"
TRIAGE_MAX_INTERVAL="${TRIAGE_MAX_INTERVAL:-360}"
TRIAGE_NOTIFY="${TRIAGE_NOTIFY:-true}"
TRIAGE_ALWAYS="${TRIAGE_ALWAYS:-false}"
TRIAGE_STRICT="${TRIAGE_STRICT:-false}"
PUSHGATEWAY_URL="${PUSHGATEWAY_URL:-http://prometheus-pushgateway:9091}"
OUTBOX_DIR="${OUTBOX_DIR:-/work/.decree/outbox}"

if [ "${DECREE_PRE_CHECK:-}" = "true" ]; then
    # shellcheck source=../lib/precheck.sh
    source "${SCRIPT_DIR}/../lib/precheck.sh"
    [ -d "$TRIAGE_REPO" ] || precheck_fail "triage" \
        "${TRIAGE_REPO} is not mounted — add '../..:/repo:ro' to the decree service"
    [ -f "${TRIAGE_REPO}/.env.shared" ] || precheck_fail "triage" \
        "${TRIAGE_REPO}/.env.shared not found — is the repo mounted read-only at ${TRIAGE_REPO}?"
    command -v curl >/dev/null 2>&1 || precheck_fail "triage" "curl not found"
    precheck_pass "triage"
    exit 0
fi

mkdir -p "$(dirname "$TRIAGE_STATE")" "$OUTBOX_DIR"

# ── Backoff ──────────────────────────────────────────────────────────────────
#
# cron/ is mounted read-only, so the schedule cannot rewrite itself. The cron
# fires often and the ROUTINE decides whether this tick is due — which keeps the
# interval a piece of state rather than a piece of configuration, and makes a
# no-op tick cost milliseconds.

GREEN_STREAK=0; LAST_RUN=0; PREV_FAILED=""
# shellcheck disable=SC1090
[ -f "$TRIAGE_STATE" ] && . "$TRIAGE_STATE"

_interval_for() {
    local streak="$1" i=0 step last=0
    for step in $TRIAGE_BACKOFF; do
        last="$step"
        [ "$i" -ge "$streak" ] && { echo "$step"; return; }
        i=$((i + 1))
    done
    # Past the end of the table, hold at the max rather than growing forever.
    [ "$last" -gt "$TRIAGE_MAX_INTERVAL" ] && last="$TRIAGE_MAX_INTERVAL"
    echo "$TRIAGE_MAX_INTERVAL"
}

NOW="$(date +%s)"
INTERVAL_MIN="$(_interval_for "$GREEN_STREAK")"
DUE=$(( LAST_RUN + INTERVAL_MIN * 60 ))

if [ "$TRIAGE_ALWAYS" != "true" ] && [ "$NOW" -lt "$DUE" ]; then
    echo "Not due for $(( (DUE - NOW + 59) / 60 ))m (green streak ${GREEN_STREAK}, checking every ${INTERVAL_MIN}m)."
    exit 0
fi

# ── Run every enabled service's own test ─────────────────────────────────────

set -a
# shellcheck disable=SC1091
. "${TRIAGE_REPO}/.env.shared"
set +a
export IN_CONTAINER=1

PASSED=(); FAILED=(); SKIPPED=()

for _t in "${TRIAGE_REPO}"/{ai,services,nas,hosting}/*/exist.test.sh; do
    [ -f "$_t" ] || continue
    _dir="$(dirname "$_t")"
    _slug="$(basename "$_dir")"
    _cat="$(basename "$(dirname "$_dir")")"
    _var="EXIST_IS_${_cat^^}_${_slug^^}"; _var="${_var//-/_}"
    if [ "${!_var:-false}" != "true" ]; then
        SKIPPED+=("$_slug")
        continue
    fi

    _out="$(cd "$_dir" && timeout 120 bash "$_t" 2>&1)" && _rc=0 || _rc=$?
    if [ "$_rc" -eq 0 ]; then
        PASSED+=("$_slug")
        echo "  ok    ${_slug}"
    else
        FAILED+=("$_slug")
        echo "  FAIL  ${_slug}"
        # The failing lines only. A passing probe's output is noise here; the
        # whole point is that what is broken should be the thing you can see.
        printf '%s\n' "$_out" | grep -iE "FAIL|WARN|✗|error" | sed 's/^/          /' | head -8
    fi

    # Per-service gauge, so Grafana can show a wall of green/red without anyone
    # authoring a service-health cron file per service.
    printf '# TYPE exist_service_healthy gauge\nexist_service_healthy{service="%s",category="%s"} %s\n' \
        "$_slug" "$_cat" "$([ "$_rc" -eq 0 ] && echo 1 || echo 0)" \
        | curl -sS --max-time 5 --data-binary @- \
            "${PUSHGATEWAY_URL}/metrics/job/triage/instance/${_slug}" >/dev/null 2>&1 || true
done

TOTAL=$(( ${#PASSED[@]} + ${#FAILED[@]} ))
echo ""
echo "Triage: ${#PASSED[@]}/${TOTAL} healthy, ${#SKIPPED[@]} not enabled."

# ── Report ───────────────────────────────────────────────────────────────────

{
    printf '# Stack status\n\n'
    printf 'Checked %s — %s of %s services healthy.\n\n' \
        "$(date -u '+%Y-%m-%d %H:%M UTC')" "${#PASSED[@]}" "$TOTAL"
    if [ "${#FAILED[@]}" -gt 0 ]; then
        printf '## Not working\n\n'
        printf -- '- **%s** — `./existential.sh test %s`\n' "${FAILED[@]}" 2>/dev/null \
            || for f in "${FAILED[@]}"; do printf -- '- **%s** — `./existential.sh test %s`\n' "$f" "$f"; done
        printf '\n'
    fi
    printf '## Working\n\n'
    [ "${#PASSED[@]}" -gt 0 ] && printf -- '- %s\n' "${PASSED[@]}"
    printf '\n## Not enabled\n\n'
    [ "${#SKIPPED[@]}" -gt 0 ] && printf -- '- %s\n' "${SKIPPED[@]}"
} > "$TRIAGE_REPORT" 2>/dev/null || true

# The same report into the run dir, when there is one. $TRIAGE_REPORT lives on a
# volume inside the container, which is exactly where nobody can reach it after
# the stack is torn down; $message_dir is copied out with the rest of the run's
# evidence. Costs one cp and makes e2e's per-service verdict readable.
[ -n "$message_dir" ] && [ -d "$message_dir" ] \
    && cp "$TRIAGE_REPORT" "${message_dir}/status.md" 2>/dev/null || true

# ── Notify on CHANGE only ────────────────────────────────────────────────────

NOW_FAILED="$(printf '%s ' "${FAILED[@]+"${FAILED[@]}"}" | tr -s ' ')"
NOW_FAILED="${NOW_FAILED% }"

if [ "$TRIAGE_NOTIFY" = "true" ] && [ "$NOW_FAILED" != "$PREV_FAILED" ]; then
    _broke=""; _fixed=""
    for s in $NOW_FAILED;  do printf '%s\n' $PREV_FAILED | grep -qx "$s" || _broke+="${s} "; done
    for s in $PREV_FAILED; do printf '%s\n' $NOW_FAILED  | grep -qx "$s" || _fixed+="${s} "; done

    if [ -n "$_broke" ] || [ -n "$_fixed" ]; then
        # Build the frontmatter values as plain variables first. Inlining them
        # in the heredoc broke two ways, and both only showed up on the failure
        # path -- the one path this routine exists for:
        #   - the title carries a literal ": " ("Stack: x stopped working"), so
        #     it must be QUOTED. Unquoted, the message is invalid YAML; decree
        #     fails to parse it, never writes run.json, and so re-runs the same
        #     triage message on every 5-minute tick forever.
        #   - ${v:+a}${v:-b} is not an if/else. When v is set, ${v:-b} expands
        #     to v, not to nothing, so the set branch emitted "high" + "hermes "
        #     = "highhermes". It only looked correct while nothing was broken.
        _title=""
        [ -n "$_broke" ] && _title="Stack: ${_broke% } stopped working"
        [ -n "$_fixed" ] && _title="${_title:+${_title} · }${_fixed% } recovered"
        if [ -n "$_broke" ]; then
            _priority="high";    _tags="warning"
        else
            _priority="default"; _tags="white_check_mark"
        fi
        # Double-quoted YAML scalar: backslashes first, then quotes.
        _title_yaml="${_title//\\/\\\\}"
        _title_yaml="${_title_yaml//\"/\\\"}"

        cat > "${OUTBOX_DIR}/triage-$(date +%s%N).md" << NOTIFY
---
routine: notify
ntfy_title: "${_title_yaml}"
ntfy_priority: ${_priority}
ntfy_tags: ${_tags}
---
${_broke:+Not working: ${_broke% }
}${_fixed:+Recovered: ${_fixed% }
}
${#PASSED[@]} of ${TOTAL} services healthy.
Details: docker exec decree cat ${TRIAGE_REPORT}
NOTIFY
        echo "Notified: ${_broke:+broke=${_broke% }}${_fixed:+ fixed=${_fixed% }}"
    fi
fi

# ── Persist ──────────────────────────────────────────────────────────────────

if [ "${#FAILED[@]}" -eq 0 ]; then
    GREEN_STREAK=$((GREEN_STREAK + 1))
else
    # Any failure puts it back on the tightest interval. Recovering from broken
    # is exactly when someone is watching and wants fast feedback.
    GREEN_STREAK=0
fi

{
    printf 'GREEN_STREAK=%s\n' "$GREEN_STREAK"
    printf 'LAST_RUN=%s\n' "$NOW"
    printf 'PREV_FAILED=%q\n' "$NOW_FAILED"
} > "$TRIAGE_STATE"

NEXT="$(_interval_for "$GREEN_STREAK")"
if [ "${#FAILED[@]}" -eq 0 ]; then
    echo "All green (streak ${GREEN_STREAK}). Next check in ${NEXT}m."
else
    echo "Next check in ${NEXT}m. Fix with: ./existential.sh test services"
fi

# Under TRIAGE_STRICT the exit code IS the verdict — the mode e2e runs in, where
# a broken service must fail the run and nothing is watching Grafana or ntfy.
if [ "$TRIAGE_STRICT" = "true" ] && [ "${#FAILED[@]}" -gt 0 ]; then
    echo "TRIAGE_STRICT: ${#FAILED[@]} service(s) failed — ${FAILED[*]}" >&2
    exit 1
fi

# Otherwise always exit 0, even with services down. Triage's job is to REPORT
# health, and it did that — a non-zero exit would tell decree the routine itself
# failed, so it would retry the whole suite three times and then dead-letter. The
# health signal rides the exist_service_healthy gauge (per service, so Grafana can
# show exactly which one) and the ntfy notification, not this exit code.
exit 0
