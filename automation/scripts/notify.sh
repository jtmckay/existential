#!/usr/bin/env bash
# Notify
#
# Sends the message body to ntfy, stripping frontmatter and whitespace.
#
#   decree emit --machine notify --param ntfy_title='My Alert' <<<'Something happened.'
set -euo pipefail

ntfy_url="${NTFY_URL:-http://ntfy:80}"
ntfy_topic="$DECREE_DATA_NTFY_TOPIC"
ntfy_token="${NTFY_TOKEN:-}"
# ntfy denies every publish by default (auth-default-access: deny-all in
# server.yml), so one of these two must be set. The bot user is created by ntfy's
# entrypoint on first boot and needs nothing from you; a token is the opt-in
# alternative and wins when both are present.
ntfy_user="${NTFY_USER:-}"
ntfy_password="${NTFY_PASSWORD:-}"
ntfy_title="$DECREE_DATA_NTFY_TITLE"
ntfy_priority="$DECREE_DATA_NTFY_PRIORITY"
ntfy_tags="$DECREE_DATA_NTFY_TAGS"

# These three become HTTP headers below. Params are attacker-influenceable
# (email/webhook → inbox), so strip CR/LF to prevent header injection.
strip_crlf() { printf '%s' "${1//[$'\r\n']/}"; }
ntfy_title="$(strip_crlf "$ntfy_title")"
ntfy_priority="$(strip_crlf "$ntfy_priority")"
ntfy_tags="$(strip_crlf "$ntfy_tags")"

telegram_bot_token="${TELEGRAM_BOT_TOKEN:-}"
telegram_chat_id="${TELEGRAM_CHAT_ID:-}"

# Strip YAML frontmatter and leading/trailing whitespace
body=$(awk 'NR==1 && /^---$/{skip=1; next} skip && /^---$/{skip=0; next} !skip' "$DECREE_MESSAGE" | sed '/./,$!d' | sed -e :a -e '/^[[:space:]]*$/{ $d; N; ba; }')

if [ -z "$body" ]; then
    echo "Empty message body, skipping notification."
    exit 0
fi

# Build curl args
# --data-raw prevents curl from interpreting @ as a filename.
# -f matters as much as -s: without it curl exits 0 on an HTTP error, so a
# publish ntfy REJECTED (403 when auth-default-access is deny-all and no token
# is set — see `./existential.sh run ntfy setup`) was reported as "sent" and the
# Telegram fallback never fired.
args=(-fsS --data-raw "$body")

if [ -n "$ntfy_token" ]; then
    args+=(-H "Authorization: Bearer $ntfy_token")
elif [ -n "$ntfy_user" ] && [ -n "$ntfy_password" ]; then
    args+=(-u "${ntfy_user}:${ntfy_password}")
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
    echo "ntfy rejected or unreachable — falling back to Telegram" >&2
    telegram_text="${ntfy_title:+[${ntfy_title}] }${body}"
    if curl -fsSL \
        -d "chat_id=${telegram_chat_id}" \
        --data-urlencode "text=${telegram_text}" \
        "https://api.telegram.org/bot${telegram_bot_token}/sendMessage" \
        >/dev/null; then
        echo "Notification sent via Telegram fallback"
    else
        echo "Telegram fallback also failed" >&2
        exit 1
    fi
else
    echo "ntfy rejected the publish or is unreachable, and no Telegram fallback is" >&2
    echo "configured (set TELEGRAM_BOT_TOKEN + TELEGRAM_CHAT_ID). A 403 here means" >&2
    echo "no credential reached this routine — check EXIST_NTFY_USER and" >&2
    echo "EXIST_NTFY_PASSWORD in .env.shared, then: docker compose up -d automation" >&2
    exit 1
fi
