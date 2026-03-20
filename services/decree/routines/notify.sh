#!/usr/bin/env bash
# Notify
#
# Sends the message body to ntfy, stripping frontmatter and whitespace.
set -euo pipefail

message_file="${message_file:-}"
message_id="${message_id:-}"
message_dir="${message_dir:-}"
chain="${chain:-}"
seq="${seq:-}"

if [ "${DECREE_PRE_CHECK:-}" = "true" ]; then
    command -v curl >/dev/null 2>&1 || { echo "curl not found" >&2; exit 1; }
    exit 0
fi

ntfy_url="${ntfy_url:-${NTFY_URL:-http://ntfy:80}}"
ntfy_topic="${ntfy_topic:-decree}"
ntfy_token="${ntfy_token:-${NTFY_TOKEN:-}}"
ntfy_title="${ntfy_title:-}"
ntfy_priority="${ntfy_priority:-}"
ntfy_tags="${ntfy_tags:-}"

# Strip YAML frontmatter and leading/trailing whitespace
body=$(sed '1{/^---$/d}; /^---$/,/^---$/d' "$message_file" | sed '/./,$!d' | sed -e :a -e '/^[[:space:]]*$/{ $d; N; ba; }')

if [ -z "$body" ]; then
    echo "Empty message body, skipping notification."
    exit 0
fi

# Build curl args
args=(-s -d "$body")

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

curl "${args[@]}" "${ntfy_url}/${ntfy_topic}"
echo ""
echo "Notification sent to ${ntfy_topic}"
