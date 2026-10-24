#!/usr/bin/env bash
# Notify
#
# Sends the message body to ntfy, stripping frontmatter and whitespace.
#
#   decree emit --machine notify --param ntfy_title='My Alert' <<<'Something happened.'
set -euo pipefail

ntfy_url="${NTFY_URL:-http://ntfy:80}"
ntfy_topic="$DECREE_DATA_NTFY_TOPIC"
# ntfy denies every publish by default (auth-default-access: deny-all in
# server.yml). The bot user is created by ntfy's entrypoint on first boot and
# needs nothing from you.
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

# Strip YAML frontmatter and leading/trailing whitespace
body=$(awk 'NR==1 && /^---$/{skip=1; next} skip && /^---$/{skip=0; next} !skip' "$DECREE_MESSAGE" | sed '/./,$!d' | sed -e :a -e '/^[[:space:]]*$/{ $d; N; ba; }')

if [ -z "$body" ]; then
    echo "Empty message body, skipping notification."
    exit 0
fi

# --data-raw prevents curl from interpreting @ as a filename. -f matters as much
# as -s: without it curl exits 0 on an HTTP error, so a publish ntfy rejected
# would be reported as sent.
args=(-fsS --data-raw "$body")
if [ -n "$ntfy_user" ] && [ -n "$ntfy_password" ]; then
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
else
    echo "ntfy rejected the publish or is unreachable. A 403 here means no credential" >&2
    echo "reached this routine — check EXIST_NTFY_USER and EXIST_NTFY_PASSWORD in" >&2
    echo ".env.shared, then: docker compose up -d automation" >&2
    exit 1
fi
