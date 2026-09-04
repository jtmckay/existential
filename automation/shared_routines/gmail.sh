#!/usr/bin/env bash
# Gmail
#
# Saves each incoming email in its entirety to EMAIL_DIR.
#
#   $from, $to, $subject, $date, $gmail_id, $thread_id,
#   $labels, $has_attachments, $message_file
#
# Example inbox message (.decree/inbox/gmail-<id>.md):
#
#   ---
#   routine: gmail
#   msg_id: 'gmail-18f2a3b4c5d6e7f8'
#   gmail_id: '18f2a3b4c5d6e7f8'
#   thread_id: '18f2a3b4c5d6e7f8'
#   from: 'Sender Name <sender@example.com>'
#   to: 'you@example.com'
#   subject: 'Hello'
#   date: 'Mon, 20 Apr 2026 09:00:00 +0000'
#   labels: 'INBOX,UNREAD'
#   has_attachments: false
#   ---
set -euo pipefail

message_file="${message_file:-}"
gmail_id="${gmail_id:-}"

EMAIL_DIR="${EMAIL_DIR:-/work/.decree/emails}"

if [ "${DECREE_PRE_CHECK:-}" = "true" ]; then
    # shellcheck source=../lib/precheck.sh
    source "$(dirname "${BASH_SOURCE[0]}")/../lib/precheck.sh"
    precheck_pass "gmail"
    exit 0
fi

mkdir -p "$EMAIL_DIR"
cp "$message_file" "${EMAIL_DIR}/gmail-${gmail_id}.md"
echo "Saved: ${EMAIL_DIR}/gmail-${gmail_id}.md"
