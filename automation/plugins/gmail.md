---
machine: plugin
automation: gmail
chart:
  description: File one email from gmail_sync, whole, in the emails directory.
  data:
    gmail_id: {type: string, default: ""}
    thread_id: {type: string, default: ""}
    from: {type: string, default: ""}
    to: {type: string, default: ""}
    subject: {type: string, default: ""}
    date: {type: string, default: ""}
    labels: {type: string, default: ""}
    has_attachments: {type: bool, default: false}
  initial: save
  states:
    save:
      invoke: gmail
      transitions: {done: done}
    done: {final: true}
    failed: {final: true}
scripts:
  gmail: |
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
---
# gmail

File one email from gmail_sync, whole, in the emails directory.
