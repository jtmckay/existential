---
machine: plugin
automation: gmail-inbox
name: Gmail
tagline: New mail every 15 minutes, as decree messages other flows act on
docs: /docs/integrations/gmail
services:
  - EXIST_IS_SERVICES_AUTOMATION
needs:
  - gmail_sync
cron:
  gmail-sync: |
    ---
    cron: "*/15 * * * *"
    machine: gmail_sync
    ---

    Fetch new Gmail messages and write them to the decree inbox.
---

Grant read-only access once, in a browser:
  ./existential.sh run automation gmail-sync
