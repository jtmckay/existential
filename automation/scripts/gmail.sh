#!/usr/bin/env bash
# gmail — file each email gmail_sync emits, whole, in EMAIL_DIR.
#
# The message is the email: its headers are the params (gmail_id, from,
# subject, …) and its body the message body.
set -euo pipefail

EMAIL_DIR="${EMAIL_DIR:-/data/emails}"

mkdir -p "$EMAIL_DIR"
cp "$DECREE_MESSAGE" "${EMAIL_DIR}/gmail-${DECREE_DATA_GMAIL_ID}.md"
echo "Saved: ${EMAIL_DIR}/gmail-${DECREE_DATA_GMAIL_ID}.md"
