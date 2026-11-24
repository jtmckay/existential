---
name: gmail-inbox
x-exist-project: automation
x-exist-title: Gmail
x-exist-tagline: New mail every 15 minutes, as decree messages other flows act on
x-exist-docs: /docs/integrations/gmail
x-exist-services:
  - EXIST_IS_SERVICES_AUTOMATION
needs:
  - gmail_sync
cron:
  gmail-sync.md: |
    ---
    cron: "*/15 * * * *"
    machine: gmail_sync
    ---

    Fetch new Gmail messages and write them to the decree inbox.
---

Grant read-only access once, in a browser:
  ./existential.sh run automation gmail-sync
