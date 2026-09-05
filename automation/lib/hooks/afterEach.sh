#!/usr/bin/env bash
# shellcheck disable=SC2154  # message_file / message_dir / chain are injected
# into the environment by decree before it runs this hook; no hook assigns
# them itself.
# Fires after every message attempt (success or failure).
# Pushes metrics to Prometheus Pushgateway and a summary log to Loki.

PUSHGATEWAY_URL="${PUSHGATEWAY_URL:-http://prometheus-pushgateway:9091}"
LOKI_URL="${LOKI_URL:-http://loki:3100}"

# decree's own grouping id for this run — stable across retries of the SAME
# message, but not across a hop like outbox-relay.sh, where the relayed
# message gets a fresh chain regardless of what the original one was (see
# correlation_id below for the field that survives that hop instead).
chain="${chain:-unknown}"

# Read routine and trigger from message frontmatter (reliable vs. parsing message_id)
routine=$(grep -m1 '^routine:' "${message_file}" 2>/dev/null | sed 's/^routine:[[:space:]]*//' || true)
trigger=$(grep -m1 '^trigger:' "${message_file}" 2>/dev/null | sed 's/^trigger:[[:space:]]*//' || true)
routine="${routine:-unknown}"
trigger="${trigger:-unknown}"
trigger_type="${trigger%%:*}"

# Optional, sparse: whichever "sub thing" this run actually did, in whatever
# terms the routine itself finds useful — e.g. minio-router writes
# `subroutine: <processor-name>` onto the file-processor message it queues, so
# the Grafana table can show which processor ran, not just that file-processor
# ran. Empty for routines that have no such distinction. Not a decree field —
# purely a convention any routine's message frontmatter can opt into.
subroutine=$(grep -m1 '^subroutine:' "${message_file}" 2>/dev/null | sed 's/^subroutine:[[:space:]]*//' || true)

# Same shape as subroutine: optional, opt-in, not a decree field. Lets a flow
# that hops across several fresh decree chains (see outbox-relay.sh — every
# relayed message gets its own chain, correlation_id is the only thread tying
# them together) still be found as one thing in Grafana: `{job="decree"} |=
# "correlation_id=<value>"`. Deliberately NOT a Prometheus label or a Loki
# stream label — both are indexed, low-cardinality-only by design, and a
# correlation_id is one-per-flow, unbounded. It goes in the log line instead,
# same as message_id already does, which Loki handles fine at any cardinality.
correlation_id=$(grep -m1 '^correlation_id:' "${message_file}" 2>/dev/null | sed 's/^correlation_id:[[:space:]]*//' || true)

exit_code="${DECREE_ROUTINE_EXIT_CODE:-1}"
attempt="${DECREE_ATTEMPT:-1}"
final="${DECREE_FINAL_ATTEMPT:-false}"
success=0
[ "$exit_code" = "0" ] && success=1

duration=0
if [ -f "${message_dir}/routine.log" ]; then
    # decree's own format_duration() writes plain seconds under a minute
    # ("113s") but "<m>m<ss>s" at or above it ("1m53s") — triage alone runs
    # long enough to hit the second form on nearly every cron tick. The old
    # pattern only matched the first: sed leaves a non-matching line
    # untouched, so on a miss `dur` silently became the ENTIRE raw log line
    # ("[decree] duration 1m53s end 2026-09-05T..."), unquoted and multi-word,
    # which corrupts every field after it once this gets `| logfmt`'d in
    # Grafana — the literal timestamp in it is exactly the "columns full of
    # dates" symptom this was causing on every single triage run.
    dur_token=$(grep -m1 '\[decree\] duration' "${message_dir}/routine.log" 2>/dev/null \
        | sed -E 's/.*duration ([0-9]+m[0-9]+s|[0-9]+s) end.*/\1/' || true)
    if [[ "$dur_token" =~ ^([0-9]+)m([0-9]+)s$ ]]; then
        duration=$(( ${BASH_REMATCH[1]} * 60 + ${BASH_REMATCH[2]} ))
    elif [[ "$dur_token" =~ ^([0-9]+)s$ ]]; then
        duration="${BASH_REMATCH[1]}"
    fi
fi

# --- Prometheus Pushgateway ---
printf \
'# TYPE decree_run_success gauge
decree_run_success{trigger_type="%s"} %s
# TYPE decree_run_duration_seconds gauge
decree_run_duration_seconds{trigger_type="%s"} %s
# TYPE decree_run_attempts gauge
decree_run_attempts{trigger_type="%s"} %s
' \
    "$trigger_type" "$success" \
    "$trigger_type" "$duration" \
    "$trigger_type" "$attempt" \
    | curl --silent --show-error \
        --data-binary @- \
        "${PUSHGATEWAY_URL}/metrics/job/decree/instance/${routine}" 2>/dev/null || true

# --- Loki structured summary log ---
now_ns=$(date +%s%N)
msg_id=$(basename "${message_dir}")
log_line="message_id=${msg_id} chain=${chain} routine=${routine} subroutine=${subroutine} trigger=${trigger} correlation_id=${correlation_id} exit_code=${exit_code} attempts=${attempt} duration_s=${duration} final=${final}"

printf '{"streams":[{"stream":{"job":"decree","routine":"%s","trigger_type":"%s","exit_code":"%s"},"values":[["%s","%s"]]}]}' \
    "$routine" "$trigger_type" "$exit_code" "$now_ns" "$log_line" \
    | curl --silent --show-error \
        -H "Content-Type: application/json" \
        --data-binary @- \
        "${LOKI_URL}/loki/api/v1/push" 2>/dev/null || true

/work/.decree/lib/hooks/config-watch.sh
