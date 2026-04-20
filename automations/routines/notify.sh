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

curl "${args[@]}" "${ntfy_url}/${ntfy_topic}"
echo ""
echo "Notification sent to ${ntfy_topic}"
