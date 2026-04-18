#!/usr/bin/env bash
# Gmail
#
# Saves each incoming email in its entirety to EMAIL_DIR.
#
#   $from, $to, $subject, $date, $gmail_id, $thread_id,
#   $labels, $has_attachments, $message_file
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
