#!/usr/bin/env bash
# Notify
#
# Sends the message body to ntfy, stripping frontmatter and whitespace.
#
# Example inbox message:
#
#   ---
#   routine: notify
#   ntfy_topic: 'alerts'
#   ntfy_title: 'My Alert'
#   ntfy_priority: 'high'
#   ntfy_tags: 'warning'
#   ---
#   Something happened that needs your attention.
set -euo pipefail

message_file="${message_file:-}"

if [ "${DECREE_PRE_CHECK:-}" = "true" ]; then
    # shellcheck source=../lib/precheck.sh
    source "$(dirname "${BASH_SOURCE[0]}")/../lib/precheck.sh"
    command -v curl >/dev/null 2>&1 || precheck_fail "notify" "curl not found"
    command -v awk  >/dev/null 2>&1 || precheck_fail "notify" "awk not found"
    precheck_pass "notify"
    exit 0
fi

ntfy_url="${ntfy_url:-${NTFY_URL:-http://ntfy:80}}"
ntfy_topic="${ntfy_topic:-decree}"
ntfy_token="${ntfy_token:-${NTFY_TOKEN:-}}"
ntfy_title="${ntfy_title:-}"
ntfy_priority="${ntfy_priority:-}"
ntfy_tags="${ntfy_tags:-}"

# These three become HTTP headers below. Frontmatter is attacker-influenceable
# (email/webhook → inbox), so strip CR/LF to prevent header injection.
strip_crlf() { printf '%s' "${1//[$'\r\n']/}"; }
ntfy_title="$(strip_crlf "$ntfy_title")"
ntfy_priority="$(strip_crlf "$ntfy_priority")"
ntfy_tags="$(strip_crlf "$ntfy_tags")"

telegram_bot_token="${TELEGRAM_BOT_TOKEN:-}"
telegram_chat_id="${TELEGRAM_CHAT_ID:-}"

# Where to record notifications that could not be delivered by any channel.
# Lives under the shared runs dir so it's pruned by clean-runs and visible
# alongside the run logs. ${message_dir} is set by the decree runtime.
runs_dir="${message_dir:-/work/.decree/runs}"
failure_log="${runs_dir}/notify-failures.log"

# Append an undelivered notification to the failure log so it can be reviewed.
log_notify_failure() {
    local reason="$1"
    {
        printf '[%s] undelivered (%s) topic=%s title=%s\n' \
            "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$reason" "$ntfy_topic" "${ntfy_title:-}"
        printf '%s\n---\n' "$body"
    } >> "$failure_log" 2>/dev/null \
        || echo "warn: could not write notify failure log at ${failure_log}" >&2
}

# Strip YAML frontmatter and leading/trailing whitespace
body=$(awk 'NR==1 && /^---$/{skip=1; next} skip && /^---$/{skip=0; next} !skip' "$message_file" | sed '/./,$!d' | sed -e :a -e '/^[[:space:]]*$/{ $d; N; ba; }')

if [ -z "$body" ]; then
    echo "Empty message body, skipping notification."
    exit 0
fi

# Build curl args
# --data-raw prevents curl from interpreting @ as a filename
args=(-s --data-raw "$body")

if [ -n "$ntfy_token" ]; then
    args+=(-H "Authorization: Bearer $ntfy_token")
fi
if [ -n "$ntfy_title" ]; then
    args+=(-H "Title: $ntfy_title")
fi
if [ -n "$ntfy_priority" ]; then
    args+=(-H "Priority: $ntfy_priority")
fi
if [ -n "$ntfy_tags" ]; then
    args+=(-H "Tags: $ntfy_tags")
fi

if curl "${args[@]}" "${ntfy_url}/${ntfy_topic}"; then
    echo ""
    echo "Notification sent to ${ntfy_topic}"
elif [[ -n "$telegram_bot_token" && -n "$telegram_chat_id" ]]; then
    echo "ntfy unreachable — falling back to Telegram" >&2
    telegram_text="${ntfy_title:+[${ntfy_title}] }${body}"
    if curl -fsSL \
        -d "chat_id=${telegram_chat_id}" \
        --data-urlencode "text=${telegram_text}" \
        "https://api.telegram.org/bot${telegram_bot_token}/sendMessage" \
        >/dev/null; then
        echo "Notification sent via Telegram fallback"
    else
        echo "Telegram fallback also failed" >&2
        log_notify_failure "ntfy+telegram unreachable"
        exit 1
    fi
else
    echo "ntfy unreachable and no Telegram fallback configured (set TELEGRAM_BOT_TOKEN + TELEGRAM_CHAT_ID)" >&2
    log_notify_failure "ntfy unreachable, no telegram fallback"
    exit 1
fi
