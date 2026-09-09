#!/usr/bin/env bash
# shellcheck disable=SC2154  # message_file / message_dir / message_id are
# injected into the environment by decree before it runs this hook.
#
# Fires once when a message exhausts max_attempts and moves to inbox/dead/.
# Queues an ntfy alert through the `notify` routine.
#
# Why a hook and not per-routine notification: "the routine gave up" is the same
# event whatever the routine was, and a routine that has already failed three
# times is the last thing that should be trusted to report itself. One hook
# covers every routine in both daemons, including ones added later.
#
# Why a notify message and not a curl straight to ntfy: notify.sh already knows
# how to authenticate (token vs. bot user), fall back to Telegram, and log what
# it could not deliver. Duplicating that here would mean two things to fix.
#
# The outbox, never the inbox. Everything the daemon produces goes through the
# relay: that is what gives the alert a real chain and seq, keeps it inside the
# depth accounting, and leaves it chainable — a later routine can pick up the
# notify message and do something else with it. Writing to inbox/ would smuggle
# a message past all of that. The cost is latency: decree relays the outbox as
# part of a later run, so an alert waits for the next routine to fire on that
# daemon (~10 minutes on this host, whose busiest backup cron is workspace-sync
# at */10). Tighten a cron if you need it sooner.

STATE_DIR="${DECREE_ALERT_STATE_DIR:-/work/.decree/runs/.alert-state}"
OUTBOX_DIR="${OUTBOX_DIR:-/work/.decree/outbox}"
# Re-alert about a routine that is STILL failing only this often. Without a
# cooldown a wedged 10-minute cron is 144 notifications a day, which is how an
# alert channel gets muted; with it you get one now and one every 6h until it
# is fixed. A routine that recovers clears its marker in afterEach.sh, so the
# next failure alerts immediately rather than waiting out the window.
COOLDOWN_MIN="${DECREE_ALERT_COOLDOWN_MIN:-360}"

routine=$(grep -m1 '^routine:' "${message_file}" 2>/dev/null | sed 's/^routine:[[:space:]]*//' || true)
routine="${routine:-unknown}"

# The loop breaker. A dead-lettered `notify` means ntfy itself is unreachable —
# queueing another notify to report that would dead-letter too, and every one of
# those would queue another. notify.sh writes those to runs/notify-failures.log
# on its own, which is where an undeliverable alert belongs.
[ "$routine" = "notify" ] && exit 0

# Frontmatter reaches decree from webhooks and email, so it is attacker-shaped
# input and this becomes a filename. Keep it to characters a routine name can
# actually have.
routine_safe=$(printf '%s' "$routine" | tr -cd 'A-Za-z0-9_-')
routine_safe="${routine_safe:-unknown}"

mkdir -p "$STATE_DIR" "$OUTBOX_DIR" 2>/dev/null || true
marker="${STATE_DIR}/${routine_safe}"

# -mmin rather than stat arithmetic: busybox and GNU find agree on it, and an
# empty result means "not older than the cooldown", i.e. we alerted recently.
if [ -f "$marker" ] && [ -z "$(find "$marker" -mmin "+${COOLDOWN_MIN}" 2>/dev/null)" ]; then
    exit 0
fi

# Which daemon this is, so the alert can name the container whose logs to read.
daemon="automation"
[ "${DECREE_BACKUP:-}" = "true" ] && daemon="automation-backup"

trigger=$(grep -m1 '^trigger:' "${message_file}" 2>/dev/null | sed 's/^trigger:[[:space:]]*//' || true)
attempts="${DECREE_MAX_RETRIES:-${DECREE_ATTEMPT:-?}}"
exit_code="${DECREE_ROUTINE_EXIT_CODE:-?}"

# The last few log lines, stripped of the ANSI colour every rclone/curl run
# emits — raw escapes render as garbage in a phone notification. Truncated
# because ntfy caps a message at 4KB and drops anything past it.
log_tail=""
if [ -f "${message_dir}/routine.log" ]; then
    log_tail=$(tail -n 12 "${message_dir}/routine.log" 2>/dev/null \
        | sed 's/\x1b\[[0-9;]*[A-Za-z]//g' \
        | cut -c1-200 \
        | head -c 1500)
fi

# Stamped before the message is written, not after: this is what starts the
# cooldown window, and a marker that is missing because the write failed would
# alert again on the very next run.
touch "$marker" 2>/dev/null || true

# Timestamped so two alerts in the same second cannot collide. The relay
# assigns the real message id, chain and seq on the way in, so nothing here
# needs to encode them (same shape as gmail-sync's outbox filename).
outfile="${OUTBOX_DIR}/dead-letter-${routine_safe}-$(date +%s).md"
{
    printf -- '---\n'
    printf 'routine: notify\n'
    printf "ntfy_title: 'Decree: %s failed'\n" "$routine_safe"
    printf "ntfy_priority: 'high'\n"
    printf "ntfy_tags: 'warning'\n"
    printf -- '---\n\n'
    printf '%s gave up after %s attempts (exit %s).\n\n' "$routine" "$attempts" "$exit_code"
    printf 'message: %s\n' "${message_id:-unknown}"
    [ -n "$trigger" ] && printf 'trigger: %s\n' "$trigger"
    printf 'daemon:  %s\n' "$daemon"
    if [ -n "$log_tail" ]; then
        printf '\n--- last log lines ---\n%s\n' "$log_tail"
    fi
    printf '\ndocker logs %s\n' "$daemon"
} > "$outfile"

echo "[onDeadLetter] queued ntfy alert for ${routine}" >&2
