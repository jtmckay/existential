#!/usr/bin/env bash
# Fires after every message attempt (success or failure).
# Pushes metrics to Prometheus Pushgateway and a summary log to Loki.

PUSHGATEWAY_URL="${PUSHGATEWAY_URL:-http://pushgateway:9091}"
LOKI_URL="${LOKI_URL:-http://loki:3100}"

# Read routine and trigger from message frontmatter (reliable vs. parsing message_id)
routine=$(grep -m1 '^routine:' "${message_file}" 2>/dev/null | sed 's/^routine:[[:space:]]*//' || true)
trigger=$(grep -m1 '^trigger:' "${message_file}" 2>/dev/null | sed 's/^trigger:[[:space:]]*//' || true)
routine="${routine:-unknown}"
trigger="${trigger:-unknown}"
trigger_type="${trigger%%:*}"

exit_code="${DECREE_ROUTINE_EXIT_CODE:-1}"
attempt="${DECREE_ATTEMPT:-1}"
final="${DECREE_FINAL_ATTEMPT:-false}"
success=0
[ "$exit_code" = "0" ] && success=1

duration=0
if [ -f "${message_dir}/routine.log" ]; then
    dur=$(grep '\[decree\] duration' "${message_dir}/routine.log" 2>/dev/null \
        | sed 's/.*duration \([0-9]*\)s.*/\1/' || true)
    [ -n "$dur" ] && duration=$dur
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
log_line="message_id=${msg_id} routine=${routine} trigger=${trigger} exit_code=${exit_code} attempts=${attempt} duration_s=${duration} final=${final}"

printf '{"streams":[{"stream":{"job":"decree","routine":"%s","trigger_type":"%s","exit_code":"%s"},"values":[["%s","%s"]]}]}' \
    "$routine" "$trigger_type" "$exit_code" "$now_ns" "$log_line" \
    | curl --silent --show-error \
        -H "Content-Type: application/json" \
        --data-binary @- \
        "${LOKI_URL}/loki/api/v1/push" 2>/dev/null || true

/work/.decree/hooks/config-watch.sh
