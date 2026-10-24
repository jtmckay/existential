#!/usr/bin/env bash
# attention-notify.sh — one ntfy message for each run that needs you.
#
# decree writes .decree/attention/<id>.md for every run that is failed,
# interrupted or waiting on a person, with the exact command that continues it.
# This turns each new one into a `notify` run: title naming the machine and what
# happened, body the file itself with its commands made runnable from the host.
# One pass; the entrypoint (ATTENTION_NOTIFY=1) runs it every few seconds.
#
# Once per run per status and state: what was sent is in $ATTENTION_SEEN, and a
# key is dropped once its file is gone, so a retried run that fails again says so.
# A `notify` run is never reported: when ntfy is what is broken, reporting it
# through ntfy would fail again, forever. This script is not a decree run, so it
# leaves no attention file of its own.
set -euo pipefail

ATTENTION_DIR="${ATTENTION_DIR:-.decree/attention}"
ATTENTION_SEEN="${ATTENTION_SEEN:-/data/attention-notified}"

touch "$ATTENTION_SEEN"
field() { sed -n "2,/^---\$/s/^$1: //p" "$2" | head -1; }

seen_now=()
for f in "$ATTENTION_DIR"/*.md; do
    [[ -f "$f" ]] || continue
    name="$(basename "$f")"
    [[ "$name" == manual-stop.md ]] && continue   # `decree stop`: you did that yourself
    machine="$(field machine "$f")"
    status="$(field status "$f")"
    state="$(field state "$f")"
    [[ "$machine" == notify ]] && continue
    if [[ "$(field kind "$f")" == run ]]; then
        key="$(field run "$f") ${status} ${state}"
    else
        key="${name} $(cksum < "$f" | cut -d' ' -f1)"   # a hold a person or tool wrote
    fi
    seen_now+=("$key")
    grep -qxF "$key" "$ATTENTION_SEEN" && continue

    case "$status" in
        waiting) title="decree: ${machine} is waiting for you in ${state}" ;;
        "")      title="decree: the queue is held by ${name}" ;;
        *)       title="decree: ${machine} ${status} in ${state}" ;;
    esac
    # The body, with decree's indented commands prefixed to run from the host.
    awk 'NR==1 && /^---$/{fm=1; next} fm && /^---$/{fm=0; next} !fm' "$f" \
        | sed -E 's/^    decree /    docker exec automation decree /' \
        | decree emit --machine notify --param ntfy_title="$title" \
            --param ntfy_priority=high --param ntfy_tags=warning >/dev/null
    echo "$key" >> "$ATTENTION_SEEN"
done

# Forget what is no longer waiting, so the next time it is, it is news again.
printf '%s\n' "${seen_now[@]+"${seen_now[@]}"}" | grep -vx '' | grep -xFf "$ATTENTION_SEEN" \
    > "${ATTENTION_SEEN}.tmp" || true
mv "${ATTENTION_SEEN}.tmp" "$ATTENTION_SEEN"
