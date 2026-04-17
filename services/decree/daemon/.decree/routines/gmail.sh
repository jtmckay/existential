#!/usr/bin/env bash
# Gmail
#
# Handles an incoming email written to the inbox by decree-gmail.
# Frontmatter fields are available as environment variables:
#
#   $from, $to, $subject, $date, $gmail_id, $thread_id,
#   $labels, $has_attachments, $message_file
#
# The full email body is in $message_file (after the --- frontmatter).
# Customize this routine to do whatever you need with each email.
set -euo pipefail

message_file="${message_file:-}"
from="${from:-}"
subject="${subject:-}"
date="${date:-}"
gmail_id="${gmail_id:-}"
labels="${labels:-}"
has_attachments="${has_attachments:-false}"

if [ "${DECREE_PRE_CHECK:-}" = "true" ]; then
    # shellcheck source=../lib/precheck.sh
    source "$(dirname "${BASH_SOURCE[0]}")/../lib/precheck.sh"
    precheck_pass "gmail"
    exit 0
fi

echo "From:        ${from}"
echo "Subject:     ${subject}"
echo "Date:        ${date}"
echo "Labels:      ${labels}"
echo "Gmail ID:    ${gmail_id}"
echo "Attachments: ${has_attachments}"
echo ""

# Strip frontmatter to get the plain email body
body=$(awk 'NR==1 && /^---$/{skip=1; next} skip && /^---$/{skip=0; next} !skip' \
    "$message_file" | sed '/./,$!d')

echo "--- Body ---"
echo "$body"

# ── Optional: queue an ntfy notification for each email ───────────────────────
# Uncomment to enqueue a notify inbox item instead of curling ntfy directly.
#
# INBOX_DIR="${INBOX_DIR:-/work/.decree/inbox}"
# ntfy_topic="${NTFY_TOPIC:-decree}"
#
# {
#     printf -- '---\n'
#     printf "routine: notify\n"
#     printf "ntfy_title: '%s'\n" "$(printf '%s' "$subject" | sed "s/'/''/g")"
#     printf "ntfy_tags: 'email'\n"
#     printf "ntfy_topic: '%s'\n" "$ntfy_topic"
#     printf -- '---\n'
#     printf '\n'
#     printf 'From: %s\n' "$from"
# } > "${INBOX_DIR}/notify-gmail-${gmail_id}.md"
