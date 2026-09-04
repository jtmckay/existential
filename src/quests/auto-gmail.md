---
name: Gmail Integration
tagline: Connect Decree to your Gmail inbox for email-driven automations
e2e: false
services:
  - var: EXIST_IS_SERVICES_AUTOMATION
    label: Decree
---

Grants Decree read-only Gmail access via OAuth 2.0. Required by the
bank transaction import and receipt split automations.
Docs: https://existential.company/docs/integrations/gmail

Setup:
  1. ./existential.sh run automation gmail-sync
     Opens a browser OAuth flow and writes credentials to
     automation/secrets/gmail/.

  2. Activate the poller — checks for new messages every 15 minutes:
       mkdir -p automation/cron/
       cp automation-examples/cron/gmail-sync.md automation/cron/
       docker compose restart automation
